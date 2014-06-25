package main

import (
	"encoding/json"
	"fmt"
	"github.com/go-martini/martini"
	"github.com/gorilla/websocket"
	"log"
	"net/http"
)

func main() {
	m := martini.New()

	r := martini.NewRouter()
	r.Get("/", func() string {
		return "hello world."
	})

	r.NotFound(func() (int, string) {
		return 404, "Dude, not found."
	})

	r.Get("/_", func(params martini.Params) string {
		l := r.All()
		commands := make([][]string, len(l))

		for index, item := range l {
			commands[index] = make([]string, 3)
			commands[index][0] = item.Method()
			commands[index][1] = item.Pattern()
			commands[index][2] = item.GetName()
		}

		result, _ := json.Marshal(commands)
		return string(result)
	})

	r.Get("/sock", func(w http.ResponseWriter, r *http.Request) {
		ws, err := websocket.Upgrade(w, r, nil, 1024, 1024)
		if _, ok := err.(websocket.HandshakeError); ok {
			http.Error(w, "Not a websocket handshake", 400)
			return
		} else if err != nil {
			log.Println(err)
			return
		}

		client := ws.RemoteAddr()
		log.Println("Client", client)

		for {
			messageType, p, err := ws.ReadMessage()
			if err != nil {
				log.Println("bye")
				log.Println(err)
				return
			}
			ws.WriteMessage(messageType, []byte(fmt.Sprintf("you wrote: %s", p)))
		}
	})

	m.Use(martini.Static("assets"))
	m.Action(r.Handle)

	m.Run()
}
