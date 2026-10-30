// Spike for #38: can ADK Go's workflow package run t4l's graph?
//
// A small version of the large lane, with every command a separate process
// and the run kept in SQLite:
//
//	plan -> approve (human) -> implement (agent) -> judge -+-> ship
//	                   |            ^                      |
//	                   |            +------ fail ----------+
//	                   +-> rejected          judge -> escalate (after max attempts)
//
//	go run . -db run.db start "feature name"   runs until the approve node waits
//	go run . -db run.db status                 shows the pending question, if any
//	go run . -db run.db resume yes|no          answers it, in a new process
//
// T4L_SPIKE_VERDICTS=fail,pass sets the judge's verdict per attempt.
// T4L_SPIKE_CLAUDE=1 makes implement call `claude -p` instead of a stub.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/glebarez/sqlite"
	"google.golang.org/genai"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"google.golang.org/adk/v2/agent"
	"google.golang.org/adk/v2/agent/workflowagent"
	"google.golang.org/adk/v2/runner"
	"google.golang.org/adk/v2/session"
	"google.golang.org/adk/v2/session/database"
	"google.golang.org/adk/v2/workflow"
)

const (
	app       = "t4l"
	user      = "lead"
	sessionID = "run"
	maxTries  = 2
)

// Work is what every node passes on. It goes through JSON when the run is
// rebuilt from SQLite, so the spike checks that it comes back typed.
type Work struct {
	Feature  string   `json:"feature"`
	Attempt  int      `json:"attempt"`
	Verdicts []string `json:"verdicts"`
}

func graph() (agent.Agent, error) {
	plan := workflow.NewFunctionNode("plan",
		func(_ agent.Context, feature string) (Work, error) {
			return Work{Feature: feature}, nil
		}, workflow.NodeConfig{})

	rerun := true
	approve := workflow.NewEmittingFunctionNode("approve",
		func(ctx agent.Context, w Work, emit func(*session.Event) error) (any, error) {
			reply, err := workflow.ResumeOrRequestInput(ctx, emit, session.RequestInput{
				InterruptID: "approve-" + ctx.InvocationID(),
				Message:     fmt.Sprintf("Approve the plan for %q? (yes/no)", w.Feature),
				Payload:     w,
			})
			if err != nil {
				return nil, err
			}
			route := "rejected"
			if s := fmt.Sprint(reply); strings.HasPrefix(s, "y") || strings.Contains(s, "payload:y") {
				route = "approved"
			}
			return nil, emitRoute(ctx, emit, route, w)
		}, workflow.NodeConfig{RerunOnResume: &rerun})

	implement := workflow.NewFunctionNode("implement",
		func(_ agent.Context, w Work) (Work, error) {
			w.Attempt++
			if os.Getenv("T4L_SPIKE_CLAUDE") == "1" {
				out, err := exec.Command("claude", "-p", "--max-turns", "1",
					fmt.Sprintf("Reply with one line: attempt %d at %s.", w.Attempt, w.Feature)).Output()
				if err != nil {
					return w, fmt.Errorf("claude -p: %w", err)
				}
				fmt.Printf("    claude: %s", out)
			}
			return w, nil
		}, workflow.NodeConfig{})

	judge := workflow.NewEmittingFunctionNode("judge",
		func(ctx agent.Context, w Work, emit func(*session.Event) error) (any, error) {
			verdicts := strings.Split(os.Getenv("T4L_SPIKE_VERDICTS"), ",")
			v := "pass"
			if w.Attempt-1 < len(verdicts) && verdicts[w.Attempt-1] != "" {
				v = verdicts[w.Attempt-1]
			}
			w.Verdicts = append(w.Verdicts, v)
			route := v
			if v == "fail" && w.Attempt >= maxTries {
				route = "exhausted"
			}
			return nil, emitRoute(ctx, emit, route, w)
		}, workflow.NodeConfig{})

	end := func(name string) *workflow.FunctionNode {
		return workflow.NewFunctionNode(name,
			func(_ agent.Context, w Work) (string, error) {
				return fmt.Sprintf("%s: %s after %d attempt(s), verdicts %v", name, w.Feature, w.Attempt, w.Verdicts), nil
			}, workflow.NodeConfig{})
	}
	ship, escalate, stop := end("ship"), end("escalate"), end("rejected")

	edges := workflow.Concat(
		workflow.Chain(workflow.Start, plan, approve),
		[]workflow.Edge{
			{From: approve, To: implement, Route: workflow.StringRoute("approved")},
			{From: approve, To: stop, Route: workflow.StringRoute("rejected")},
			{From: implement, To: judge},
			{From: judge, To: ship, Route: workflow.StringRoute("pass")},
			{From: judge, To: implement, Route: workflow.StringRoute("fail")},
			{From: judge, To: escalate, Route: workflow.StringRoute("exhausted")},
		},
	)
	return workflowagent.New(workflowagent.Config{Name: "large_lane", Description: "spike", Edges: edges})
}

// emitRoute sets the route the outgoing edges match on. The event carries the
// node's output, so the node itself must return nil.
func emitRoute(ctx agent.Context, emit func(*session.Event) error, route string, w Work) error {
	ev := session.NewEvent(ctx, ctx.InvocationID())
	ev.Routes = []string{route}
	ev.Output = w
	return emit(ev)
}

func main() {
	db := flag.String("db", "run.db", "SQLite file that keeps the run")
	flag.Parse()
	if err := run(context.Background(), *db, flag.Args()); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, db string, args []string) error {
	if len(args) == 0 {
		return errors.New("usage: start <feature> | status | resume <reply>")
	}
	svc, err := database.NewSessionService(sqlite.Open(db), &gorm.Config{Logger: logger.Discard})
	if err != nil {
		return err
	}
	if err := database.AutoMigrate(svc); err != nil {
		return err
	}
	root, err := graph()
	if err != nil {
		return err
	}
	r, err := runner.New(runner.Config{AppName: app, Agent: root, SessionService: svc})
	if err != nil {
		return err
	}

	var msg *genai.Content
	switch args[0] {
	case "start":
		if len(args) < 2 {
			return errors.New("start needs a feature name")
		}
		if _, err := svc.Create(ctx, &session.CreateRequest{AppName: app, UserID: user, SessionID: sessionID}); err != nil {
			return err
		}
		msg = genai.NewContentFromText(args[1], genai.RoleUser)
	case "status", "resume":
		id, prompt, err := pending(ctx, svc)
		if err != nil {
			return err
		}
		if id == "" {
			fmt.Println("nothing is waiting")
			return nil
		}
		if args[0] == "status" || len(args) < 2 {
			fmt.Printf("waiting: %s (%s)\n", prompt, id)
			return nil
		}
		msg = &genai.Content{Role: genai.RoleUser, Parts: []*genai.Part{{FunctionResponse: &genai.FunctionResponse{
			ID: id, Name: workflow.WorkflowInputFunctionCallName, Response: map[string]any{"payload": args[1]},
		}}}}
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}

	for ev, err := range r.Run(ctx, user, sessionID, msg, agent.RunConfig{}) {
		if err != nil {
			return err
		}
		show(ev)
	}
	return nil
}

// pending finds a request for input with no answer yet in the stored events.
func pending(ctx context.Context, svc session.Service) (id, prompt string, err error) {
	resp, err := svc.Get(ctx, &session.GetRequest{AppName: app, UserID: user, SessionID: sessionID})
	if err != nil {
		return "", "", err
	}
	asked := map[string]string{}
	var order []string
	for ev := range resp.Session.Events().All() {
		if ev.Content == nil {
			continue
		}
		for _, p := range ev.Content.Parts {
			if fc := p.FunctionCall; fc != nil && fc.Name == workflow.WorkflowInputFunctionCallName {
				asked[fc.ID] = fmt.Sprint(fc.Args["message"])
				order = append(order, fc.ID)
			}
			if fr := p.FunctionResponse; fr != nil {
				delete(asked, fr.ID)
			}
		}
	}
	for i := len(order) - 1; i >= 0; i-- {
		if m, ok := asked[order[i]]; ok {
			return order[i], m, nil
		}
	}
	return "", "", nil
}

func show(ev *session.Event) {
	var parts []string
	if ev.Output != nil {
		b, _ := json.Marshal(ev.Output)
		parts = append(parts, "output="+string(b))
	}
	if len(ev.Routes) > 0 {
		parts = append(parts, "routes="+strings.Join(ev.Routes, ","))
	}
	if ev.RequestedInput != nil {
		parts = append(parts, "asks="+ev.RequestedInput.Message)
	}
	if len(parts) > 0 {
		fmt.Printf("  [%s] %s\n", ev.Author, strings.Join(parts, " "))
	}
}
