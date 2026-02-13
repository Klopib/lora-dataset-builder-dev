FROM pytorch/pytorch:2.5.1-cuda12.1-cudnn9-runtime
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /workspace
COPY requirements.txt /workspace/requirements.txt
RUN pip install --no-cache-dir -r /workspace/requirements.txt
COPY app /workspace/app
EXPOSE 8080
CMD ["uvicorn", "app.florence_api:app", "--host", "0.0.0.0", "--port", "8080"]
