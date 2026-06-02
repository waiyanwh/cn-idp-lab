FROM python:3.12-slim

WORKDIR /app
COPY app.py /app/app.py

RUN addgroup --system app && adduser --system --ingroup app app
USER app

ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"

CMD ["python", "/app/app.py"]

