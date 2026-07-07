#!/bin/bash

generate_html_report() {
    load_config
    get_version

    REPORT_DIR="$PROJECT_ROOT/reports"
    REPORT_FILE="$REPORT_DIR/health-report.html"

    mkdir -p "$REPORT_DIR"

    section "PROJECT PHOENIX HTML REPORT"

    cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Project Phoenix Health Report</title>
    <style>
        body {
            background: #111;
            color: #f5f5f5;
            font-family: Arial, sans-serif;
            padding: 40px;
        }
        .card {
            max-width: 800px;
            margin: auto;
            background: #1c1c1c;
            border: 1px solid #ff8c00;
            border-radius: 12px;
            padding: 30px;
        }
        h1 {
            color: #ff8c00;
        }
        .status {
            color: #00ff88;
            font-size: 1.4em;
            font-weight: bold;
        }
        code {
            color: #ffd27f;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>🦅 Project Phoenix</h1>
        <p><strong>Rise. Recover. Restore.</strong></p>

        <h2>Health Report</h2>

        <p class="status">READY FOR DISASTER RECOVERY</p>

        <p><strong>Version:</strong> $VERSION</p>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Project:</strong> $PROJECT_NAME</p>
        <p><strong>Source:</strong> <code>$SOURCE</code></p>
        <p><strong>Destination:</strong> <code>${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION}</code></p>

        <h2>Source Size</h2>
        <pre>$(du -sh "$SOURCE" 2>/dev/null || echo "Unable to read source")</pre>

        <h2>Notes</h2>
        <p>This is a lightweight static HTML report. No database or web server required.</p>
    </div>
</body>
</html>
EOF

    log_success "HTML report generated: $REPORT_FILE"
}