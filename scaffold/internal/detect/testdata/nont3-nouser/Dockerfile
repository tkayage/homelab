# Non-T3 fixture: EXPOSE present but no non-root USER — must emit a USER warning.
FROM alpine:3.20
WORKDIR /srv
COPY . .
EXPOSE 5000
CMD ["/srv/run"]
