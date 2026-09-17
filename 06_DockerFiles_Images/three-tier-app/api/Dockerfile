FROM python:3.12-slim

WORKDIR /app

# Dependencies before source, so editing app.py does not reinstall flask.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as an unprivileged user rather than root.
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

ENV PYTHONUNBUFFERED=1
EXPOSE 5000
CMD ["python", "app.py"]
