FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 CLASSROOM_DATA_DIR=/data
WORKDIR /app
COPY server/requirements.txt /app/server/requirements.txt
RUN pip install --no-cache-dir -r /app/server/requirements.txt && useradd --uid 10001 --create-home appuser && mkdir /data && chown appuser:appuser /data
COPY server /app/server
COPY content/sets_unit.json /app/content/sets_unit.json
USER appuser
EXPOSE 8080
CMD ["gunicorn", "server.app:create_app()", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", "--timeout", "30", "--access-logfile", "-"]
