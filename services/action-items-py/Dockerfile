FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY activities.py worker.py transcript_pb2.py action_items_pb2.py dtos_pb2.py ./
CMD ["python", "worker.py"]
