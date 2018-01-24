FROM alpine:latest
RUN mkdir /app
COPY /build /app
CMD ["/app/example-go"]
