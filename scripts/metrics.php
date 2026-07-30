<?php
// The URL you want to monitor. 
// You can also pass this dynamically via ?url=https://example.com
$url = isset($_GET['url']) ? $_GET['url'] : "https://example.com";

// Initialize cURL
$ch = curl_init($url);

// Set cURL options
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true); // Follow redirects
curl_setopt($ch, CURLOPT_MAXREDIRS, 5);         // Limit redirects to prevent infinite loops
curl_setopt($ch, CURLOPT_TIMEOUT, 5);          // 5 second timeout
curl_setopt($ch, CURLOPT_USERAGENT, "Prometheus-PHP-Prober/1.0");
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true); // Set to true in production if SSL is strictly required

// Execute the request
curl_exec($ch);

// Extract the required metrics
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$total_time = curl_getinfo($ch, CURLINFO_TOTAL_TIME); // Time in seconds (float)

// Check for cURL errors (e.g., DNS resolution failure, connection timeout)
$curl_error = curl_errno($ch);
curl_close($ch);

// Determine if the site is "up" 
// We consider it UP (1) if there are no cURL errors and the HTTP code is 2xx or 3xx.
$is_up = ($curl_error === 0 && $http_code >= 200 && $http_code < 400) ? 1 : 0;

// Set the required HTTP header for the Prometheus exposition format
header('Content-Type: text/plain; version=0.0.4');

// Output the metrics in Prometheus format
echo "# HELP nextcloudremotestatus_probe_success Displays whether or not the probe was a success (1 = up, 0 = down)\n";
echo "# TYPE nextcloudremotestatus_probe_success gauge\n";
echo "nextcloudremotestatus_probe_success{url=\"$url\"} $is_up\n\n";

echo "# HELP nextcloudremotestatus_http_status_code HTTP status code of the response\n";
echo "# TYPE nextcloudremotestatus_http_status_code gauge\n";
echo "nextcloudremotestatus_http_status_code{url=\"$url\"} $http_code\n\n";

echo "# HELP nextcloudremotestatus_probe_duration_seconds Returns how long the probe took to complete in seconds\n";
echo "# TYPE nextcloudremotestatus_probe_duration_seconds gauge\n";
echo "nextcloudremotestatus_probe_duration_seconds{url=\"$url\"} $total_time\n";
?>
