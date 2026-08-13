FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Render sets $PORT dynamically — Gradio must bind to it
ENV GRADIO_SERVER_NAME=0.0.0.0
EXPOSE 7860

CMD ["python", "main.py"]