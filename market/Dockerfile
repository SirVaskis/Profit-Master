FROM python:3.14.6-slim AS collector
WORKDIR /app
COPY tools/profit_master_saved.py /app/tools/profit_master_saved.py
COPY market /app/market
RUN useradd --create-home --uid 10001 market && mkdir /data && chown market:market /data
USER market
ENTRYPOINT ["python", "-m", "market.collector"]
CMD ["--state", "/data/collector.sqlite", "--config", "/config/client.json", "watch"]

FROM collector AS receiver
USER root
RUN pip install --no-cache-dir -r /app/market/requirements-server.txt
USER market
ENTRYPOINT ["python", "-m", "uvicorn", "market.server:app"]
CMD ["--host", "0.0.0.0", "--port", "8787", "--limit-concurrency", "16", "--timeout-keep-alive", "5"]
