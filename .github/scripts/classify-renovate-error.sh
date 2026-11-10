# Classify common network, TLS, rate-limit, and upstream HTTP failures.

classify_renovate_error() {
	local log_file="$1"
	if grep -Eqi 'ECONNRESET|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|ECONNREFUSED|socket hang up|fetch failed|rate limit|certificate verify failed|(^|[^0-9])(429|502|503|504)([^0-9]|$)' "$log_file"; then
		printf 'upstream'
	else
		printf 'configuration'
	fi
}
