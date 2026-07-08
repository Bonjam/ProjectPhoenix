#!/bin/bash

generate_html_report() {
    load_config
    get_version

    REPORT_DIR="$PROJECT_ROOT/reports"
    REPORT_FILE="$REPORT_DIR/health-report.html"
    LOGO_FILE="$PROJECT_ROOT/assets/branding/phoenix-logo-v1.svg"

    mkdir -p "$REPORT_DIR"

    section "PROJECT PHOENIX HTML REPORT"

    GENERATED_AT=$(date)

    if [ -f "$LOGO_FILE" ]; then
        LOGO_SVG=$(cat "$LOGO_FILE")
    else
        LOGO_SVG="🦅"
    fi

    if SOURCE_SIZE=$(du -sh "$SOURCE" 2>/dev/null | awk '{print $1}'); then
        :
    else
        SOURCE_SIZE="Unable to read source"
    fi

    cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Project Phoenix Health Report</title>
    <style>
        :root {
            --bg: #0f1117;
            --card: #171a23;
            --card-soft: #202431;
            --text: #f4f4f5;
            --muted: #a1a1aa;
            --gold: #ffcc66;
            --orange: #ff8c00;
            --ember: #ff4d2e;
            --green: #00d084;
            --border: rgba(255, 140, 0, 0.35);
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            background:
                radial-gradient(circle at top, rgba(255, 140, 0, 0.18), transparent 34%),
                var(--bg);
            color: var(--text);
            font-family: Arial, Helvetica, sans-serif;
            padding: 42px 20px;
        }

        .container {
            max-width: 980px;
            margin: 0 auto;
        }

        .hero {
            text-align: center;
            margin-bottom: 30px;
        }

        .logo {
            width: 150px;
            margin: 0 auto 18px;
            filter: drop-shadow(0 0 28px rgba(255, 140, 0, 0.5));
        }

        .logo svg {
            width: 100%;
            height: auto;
        }

        h1 {
            margin: 0;
            font-size: 2.4rem;
            letter-spacing: 0.08em;
            text-transform: uppercase;
        }

        .tagline {
            margin-top: 8px;
            color: var(--gold);
            font-weight: bold;
            letter-spacing: 0.14em;
            text-transform: uppercase;
        }

        .subtitle {
            margin-top: 12px;
            color: var(--muted);
        }

        .status-card {
            border: 1px solid var(--border);
            background: linear-gradient(135deg, rgba(255, 140, 0, 0.16), var(--card));
            border-radius: 20px;
            padding: 28px;
            margin-bottom: 22px;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.38);
        }

        .status {
            display: inline-block;
            background: rgba(0, 208, 132, 0.14);
            border: 1px solid rgba(0, 208, 132, 0.45);
            color: var(--green);
            padding: 10px 16px;
            border-radius: 999px;
            font-weight: bold;
            letter-spacing: 0.08em;
            text-transform: uppercase;
        }

        .status-card p {
            margin-bottom: 0;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(230px, 1fr));
            gap: 18px;
            margin-bottom: 22px;
        }

        .card {
            background: var(--card);
            border: 1px solid rgba(255, 255, 255, 0.08);
            border-radius: 18px;
            padding: 22px;
        }

        .card h2 {
            margin: 0 0 12px;
            color: var(--orange);
            font-size: 0.95rem;
            text-transform: uppercase;
            letter-spacing: 0.09em;
        }

        .value {
            font-size: 1.18rem;
            font-weight: bold;
            word-break: break-word;
        }

        .muted {
            color: var(--muted);
        }

        code {
            display: inline-block;
            max-width: 100%;
            background: var(--card-soft);
            color: var(--gold);
            padding: 6px 8px;
            border-radius: 10px;
            word-break: break-word;
        }

        .confidence-bar {
            width: 100%;
            height: 14px;
            background: var(--card-soft);
            border-radius: 999px;
            overflow: hidden;
            margin-top: 12px;
        }

        .confidence-fill {
            width: 85%;
            height: 100%;
            background: linear-gradient(90deg, var(--orange), var(--gold));
        }

        .footer {
            text-align: center;
            color: var(--muted);
            margin-top: 32px;
            font-size: 0.9rem;
        }

        .accent {
            color: var(--gold);
        }
    </style>
</head>

<body>
    <main class="container">
        <section class="hero">
            <div class="logo">
$LOGO_SVG
            </div>

            <h1>Project Phoenix</h1>
            <div class="tagline">Rise. Recover. Restore.</div>
            <p class="subtitle">Docker Disaster Recovery Health Report</p>
        </section>

        <section class="status-card">
            <span class="status">Ready for Disaster Recovery</span>
            <p class="muted">
                This static report was generated by Project Phoenix Core.
                No database, web server, or external service is required.
            </p>
        </section>

        <section class="grid">
            <div class="card">
                <h2>Version</h2>
                <div class="value">$VERSION</div>
            </div>

            <div class="card">
                <h2>Generated</h2>
                <div class="value">$GENERATED_AT</div>
            </div>

            <div class="card">
                <h2>Project</h2>
                <div class="value">$PROJECT_NAME</div>
            </div>

            <div class="card">
                <h2>Source Size</h2>
                <div class="value">$SOURCE_SIZE</div>
            </div>
        </section>

        <section class="grid">
            <div class="card">
                <h2>Source</h2>
                <p><code>$SOURCE</code></p>
            </div>

            <div class="card">
                <h2>Destination</h2>
                <p><code>${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION}</code></p>
            </div>
        </section>

        <section class="card">
            <h2>Recovery Confidence</h2>
            <div class="value">85%</div>
            <div class="confidence-bar">
                <div class="confidence-fill"></div>
            </div>
            <p class="muted">
                Early placeholder score. Future versions will calculate this from backup age,
                restore readiness, destination checks, and configuration health.
            </p>
        </section>

        <section class="card">
            <h2>Recovery Notes</h2>
            <p>
                Project Phoenix focuses on protecting the files needed to rebuild
                a self-hosted Docker environment quickly after failure.
            </p>
            <p>
                Keep your configuration, restore notes, and backup destination tested regularly.
            </p>
        </section>

        <div class="footer">
            <span class="accent">Project Phoenix</span> —
            Lightweight Docker disaster recovery using SSH and rsync.
        </div>
    </main>
</body>
</html>
EOF

    log_success "HTML report generated: $REPORT_FILE"
}