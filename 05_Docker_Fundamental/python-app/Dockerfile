FROM python:3.12-alpine

WORKDIR /app
COPY app.py .

# Unbuffered output, otherwise print() is held back and "docker logs" looks empty.
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

EXPOSE 8000
CMD ["python", "app.py"]
