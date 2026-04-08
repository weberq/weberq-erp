# =============================================================================
# WeberQ ERP — Odoo 19 Docker Image
# Base: Ubuntu 24.04 (Noble)
# =============================================================================

FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/weberq/weberq-erp"
LABEL org.opencontainers.image.description="WeberQ ERP — Odoo 19"
LABEL org.opencontainers.image.licenses="LGPL-3.0"

# ─── Env ─────────────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/venv/bin:$PATH"

# ─── System dependencies ─────────────────────────────────────────────────────
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    # Python
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    # Build tools
    build-essential \
    # XML / XSLT
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    # SASL / LDAP
    libsasl2-dev \
    libldap2-dev \
    # SSL
    libssl-dev \
    libffi-dev \
    # MySQL client (for optional connectors)
    libmysqlclient-dev \
    # Image processing (Pillow)
    libjpeg-dev \
    libjpeg8-dev \
    liblcms2-dev \
    libwebp-dev \
    # Text rendering
    libharfbuzz-dev \
    libfribidi-dev \
    libxcb1-dev \
    # PostgreSQL client
    libpq-dev \
    postgresql-client \
    # NumPy / SciPy (some Odoo modules)
    libblas-dev \
    libatlas-base-dev \
    # Node.js for Less CSS
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# ─── wkhtmltopdf (patched Qt build — required for PDF headers/footers) ───────
RUN wget -q \
    https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb \
    -O /tmp/wkhtmltox.deb \
    && dpkg -i /tmp/wkhtmltox.deb || true \
    && apt-get install -f -y \
    && rm /tmp/wkhtmltox.deb

# ─── Less CSS pre-processor (needed for Odoo backend styles) ─────────────────
RUN npm install -g less less-plugin-clean-css

# ─── Create dedicated odoo user ──────────────────────────────────────────────
RUN useradd -ms /bin/bash -d /opt/odoo odoo \
    && mkdir -p /var/lib/odoo /etc/odoo \
    && chown -R odoo:odoo /var/lib/odoo /etc/odoo

# ─── Python virtualenv ───────────────────────────────────────────────────────
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip wheel

# ─── Python dependencies (cached layer) ──────────────────────────────────────
WORKDIR /opt/odoo
COPY requirements.txt ./
RUN /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ─── Application source ───────────────────────────────────────────────────────
# NOTE: custom_addons/ submodules must be initialized locally before building
# Run: ./scripts/submodules.sh init   (or the CI will do this automatically)
COPY --chown=odoo:odoo . .

# ─── Entrypoint ──────────────────────────────────────────────────────────────
COPY --chown=odoo:odoo scripts/docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER odoo

EXPOSE 8069 8072

VOLUME ["/var/lib/odoo"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--config=/etc/odoo/odoo.conf"]
