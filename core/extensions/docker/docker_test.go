package docker

import (
	"reflect"
	"strings"
	"testing"
)

const compose = `services:
  api:
    image: alpine
    environment:
      TOKEN: ${API_TOKEN}
  "worker":
    image: alpine

volumes:
  data:
`

func TestServices(t *testing.T) {
	want := []Service{{Name: "api", Line: 2, Last: 5}, {Name: "worker", Line: 6, Last: 8}}
	if got := Services(strings.Split(compose, "\n")); !reflect.DeepEqual(got, want) {
		t.Fatalf("YAML: %+v, ждал %+v", got, want)
	}
	// недописанный файл (YAML не разбирается) — построчно
	broken := strings.Split("services:\n  api:\n    image: [\n  db:\n    image: x", "\n")
	got := Services(broken)
	if len(got) != 2 || got[0].Name != "api" || got[1].Name != "db" || got[1].Line != 4 {
		t.Fatalf("по отступам: %+v", got)
	}
	if s, ok := ServiceAt(Services(strings.Split(compose, "\n")), 4); !ok || s.Name != "api" {
		t.Fatalf("строка 4 — в api, получил %+v %v", s, ok)
	}
}

func TestIsCompose(t *testing.T) {
	for name, want := range map[string]bool{"compose.yaml": true, "/x/docker-compose.yml": true, "compose.override.yaml": true,
		"values.yaml": false, "composer.json": false} {
		if IsCompose(name) != want {
			t.Errorf("%s: ждал %v", name, want)
		}
	}
}

func TestVarsIn(t *testing.T) {
	got := VarsIn(`TOKEN: ${API_TOKEN} PORT: ${PORT:-8080} DB: $DB_URL cost: $$5 x: ${REQ:?нужна}`)
	names := []string{}
	for _, v := range got {
		names = append(names, v.Name)
		if v.Name == "PORT" && !v.Default || v.Name == "API_TOKEN" && v.Default || v.Name == "REQ" && !v.Default {
			t.Errorf("умолчание %s: %v", v.Name, v.Default)
		}
	}
	if !reflect.DeepEqual(names, []string{"API_TOKEN", "PORT", "DB_URL", "REQ"}) {
		t.Fatalf("переменные: %v ($$5 — не переменная)", names)
	}
	line := `  TOKEN: ${API_TOKEN}`
	v := VarsIn(line)[0]
	if line[v.S:v.E] != "${API_TOKEN}" {
		t.Fatalf("границы: %q", line[v.S:v.E])
	}
}

func TestEnvVars(t *testing.T) {
	got := EnvVars([]string{"# комментарий", "A=1", "export B = 2", "A=3"})
	if got["A"] != 2 || got["B"] != 3 || len(got) != 2 {
		t.Fatalf("%v", got)
	}
}

func TestStatusParts(t *testing.T) {
	c := Container{State: "exited", Status: "Exited (3) 2 minutes ago"}
	if p := StatusParts(&c); p[0].Text != "○ остановлен (код 3)" || p[0].Color != "red" {
		t.Fatalf("упал: %+v", p)
	}
	ok := Container{State: "exited", Status: "Exited (0) now"}
	if p := StatusParts(&ok); p[0].Color != "grey" {
		t.Fatalf("код 0 — серый: %+v", p)
	}
	run := Container{State: "running", Health: "healthy"}
	run.Publishers = append(run.Publishers, struct {
		PublishedPort int `json:"PublishedPort"`
	}{8080})
	p := StatusParts(&run)
	if p[0].Text != "● работает" || p[2].Text != "здоров" || p[3].Text != " · :8080" {
		t.Fatalf("работает: %+v", p)
	}
	if p := StatusParts(nil); p[0].Text != "○ не запущен" {
		t.Fatalf("нет контейнера: %+v", p)
	}
}

const dockerfile = `FROM golang:1.25 AS build
RUN go build -o /app .

FROM alpine:latest
# комментарий
RUN apk add --no-cache curl
RUN dd if=/dev/zero \
    of=/big bs=1M count=20
COPY compose.yaml /app/
WORKDIR /app
CMD ["sh"]`

func TestLayers(t *testing.T) {
	ins := LastStage(strings.Split(dockerfile, "\n"))
	if ins[0].Keyword != "FROM" || ins[0].Line != 4 || ins[2].Args != "dd if=/dev/zero of=/big bs=1M count=20" {
		t.Fatalf("последняя стадия: %+v", ins)
	}
	history := []Layer{ // как docker history: новые сверху
		{CreatedBy: `CMD ["sh"]`, Size: 0.0},
		{CreatedBy: "WORKDIR /app", Size: 0.0},
		{CreatedBy: "COPY compose.yaml /app/ # buildkit", Size: 4096.0},
		{CreatedBy: "RUN /bin/sh -c dd if=/dev/zero of=/big bs=1M count=20 # buildkit", Size: 20971520.0},
		{CreatedBy: "RUN |1 X=1 /bin/sh -c apk add --no-cache curl # buildkit", Size: 5650000.0},
		{CreatedBy: `CMD ["/bin/sh"]`, Size: 0.0},
		{CreatedBy: "ADD alpine-minirootfs.tar.gz / # buildkit", Size: 10300000.0},
	}
	sizes, total, base, ok := Assign(ins, history)
	if !ok {
		t.Fatal("ничего не сопоставилось")
	}
	want := []LayerSize{{Line: 9, Bytes: 4096}, {Line: 7, Bytes: 20971520}, {Line: 6, Bytes: 5650000}}
	if !reflect.DeepEqual(sizes, want) {
		t.Fatalf("слои: %+v, ждал %+v", sizes, want)
	}
	if base != 10300000 || total != 4096+20971520+5650000+10300000 {
		t.Fatalf("итог %d, база %d", total, base)
	}
	if Human(20971520) != "21 MB" || Human(4096) != "4.1 kB" || Human(5650000) != "5.7 MB" || SizeColor(20971520) != "blue" {
		t.Fatalf("размеры: %s %s %s %s", Human(20971520), Human(4096), Human(5650000), SizeColor(20971520))
	}
}

func TestGuessImage(t *testing.T) {
	imgs := []Image{{"other", "latest"}, {"myapp-api", "latest"}, {"myapp", "dev"}}
	if got := GuessImage("/x/MyApp", imgs); got != "myapp:dev" {
		t.Fatalf("сначала <папка>:dev, получил %s", got)
	}
	if got := GuessImage("/x/myapp", imgs[:2]); got != "myapp-api:latest" {
		t.Fatalf("затем <папка>-*, получил %s", got)
	}
}

func TestEnvEntriesAndShown(t *testing.T) {
	env := EnvEntries([]string{`DB_URL="postgres://x"`, "API_TOKEN=abcdef123", "EMPTY="})
	if env["DB_URL"].Value != "postgres://x" || env["API_TOKEN"].Line != 2 {
		t.Fatalf("%+v", env)
	}
	if got := Shown("API_TOKEN", "abcdef123"); got != "abc… (9 симв.)" {
		t.Fatalf("секрет: %q", got)
	}
	if got := Shown("DB_URL", "postgres://x"); got != "postgres://x" {
		t.Fatalf("не секрет: %q", got)
	}
	if got := Shown("EMPTY", ""); got != "(пусто)" {
		t.Fatalf("пусто: %q", got)
	}
}
