# Bare minimum HTTP servers in C

Goal of these is to provide most efficient bare minimum HTTP servers to compare other solutions against (as these should be on top on the single core tests as they are the closest to the system as possible and really doesn't handle anything from the HTTP spec).

There are the same variants for [dlang](https://dlang.org), but these are for testing ie some performance issues with used [during](https://code.dlang.org/packages/during) library.

Code taken from similar echo servers - [epoll](https://github.com/frevib/epoll-echo-server), [io_uring](https://github.com/frevib/io_uring-echo-server).
They're just slightly modified to respond with prepared HTTP response.

They can be also used to compare Linux epoll against new and shiny io_uring.
