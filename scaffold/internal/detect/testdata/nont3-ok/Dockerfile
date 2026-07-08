# Non-T3 fixture: valid EXPOSE and a non-root USER — no warnings expected.
FROM alpine:3.20
RUN addgroup -S app && adduser -S app -G app
WORKDIR /srv
COPY . .
USER app
EXPOSE 8080
CMD ["/srv/run"]
