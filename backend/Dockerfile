FROM node:20-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       python3 \
       python3-venv \
       libglib2.0-0 \
       libgl1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY requirements.txt ./
RUN python3 -m venv /opt/assessly-venv \
    && /opt/assessly-venv/bin/pip install --no-cache-dir -r requirements.txt

COPY . .

ENV NODE_ENV=production
ENV OMR_PYTHON=/opt/assessly-venv/bin/python

EXPOSE 5000

CMD ["npm", "start"]
