```
go build -ldflags="-s -w" -o app .
```

env GOMAXPROCS=1 ./app
