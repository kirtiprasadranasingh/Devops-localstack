FROM python:3.12-alpine
WORKDIR /pipeline
COPY run.sh /pipeline/run.sh
RUN chmod +x /pipeline/run.sh
ENTRYPOINT ["/pipeline/run.sh"]
