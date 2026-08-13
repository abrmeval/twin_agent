FROM python:3.12-slim

COPY src/requirements.txt ./app
RUN pip install --no-cache-dir -r ./app/requirements.txt

COPY src/ ./app
COPY info/ ./info/

# Render sets $PORT dynamically — Gradio must bind to it
ENV GRADIO_SERVER_NAME=0.0.0.0
EXPOSE 7860

WORKDIR /app

CMD ["python", "main.py"]