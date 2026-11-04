FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 BUDGET_STORE=firestore
COPY server/requirements.txt /app/server/requirements.txt
RUN pip install --no-cache-dir -r /app/server/requirements.txt && useradd --uid 10001 --create-home appuser
COPY server/chat_suggestions.py server/account_access.py server/hosted_app.py server/demo_security.py server/demo_storage.py server/judge_server.py server/court_protocol.py server/muse_image.py server/sam_evidence.py server/couple_data.py server/shared_court.py server/live_call.py server/live_transcription.py /app/server/
COPY assets/court/courtroom.png /app/assets/court/courtroom.png
USER 10001
EXPOSE 8080
CMD ["sh", "-c", "exec uvicorn hosted_app:app --app-dir server --host 0.0.0.0 --port ${PORT:-8080} --workers 1 --no-access-log"]
