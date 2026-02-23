FROM python:3.11-slim

WORKDIR /app

# Install CPU-only PyTorch first (saves ~1.5GB vs full torch)
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

# Install remaining dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ app/
COPY ml_src/ ml_src/

# Copy model files — if they're Git LFS pointers, download the real files from GitHub
COPY ml_models/ ml_models/
RUN MODEL_SIZE=$(wc -c < ml_models/ecgfounder_best.pt) && \
    if [ "$MODEL_SIZE" -lt 1000 ]; then \
        echo "Detected LFS pointers — downloading real model files from GitHub..." && \
        apt-get update && apt-get install -y --no-install-recommends curl && \
        curl -L -o ml_models/ecgfounder_best.pt \
          "https://media.githubusercontent.com/media/Sanuka23/cardiac-monitor/main/backend/ml_models/ecgfounder_best.pt" && \
        curl -L -o ml_models/xgboost_cardiac.joblib \
          "https://media.githubusercontent.com/media/Sanuka23/cardiac-monitor/main/backend/ml_models/xgboost_cardiac.joblib" && \
        apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*; \
    else \
        echo "Model files are real (not LFS pointers) — no download needed"; \
    fi

EXPOSE 7860

CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-7860}
