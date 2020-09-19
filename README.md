

```
docker build _suite/ -t httpbench
```

```

```

```
hey -n 50000 -c 256 -t 10 "http://127.0.0.1:3000/"
```


io_uring z více vláken: https://lore.kernel.org/lkml/c40338a9989a45ec38f36e5937365eca6a089795.1580170474.git.asml.silence@gmail.com/
