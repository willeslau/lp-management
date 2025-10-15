import http from 'http';

export async function obtainRange(): Promise<number | undefined> {
    const params = await fetchMetrics();

    if (params.metrics.coverage_high < 0.6 && params.metrics.coverage_low < 0.6) {
        console.log("coverage accuracy not high enough");
        return undefined;
    }

    console.log("volatility range", params.range);
    return params.range * 3;
}

async function fetchMetrics(): Promise<any> {
  const options: http.RequestOptions = {
    hostname: '127.0.0.1',
    port: 5001,
    path: '/calculate', // adjust to your actual endpoint
    method: 'GET',
    headers: {
      'Accept': 'application/json',
    },
  };

  const data = await new Promise<string>((resolve, reject) => {
    const req = http.request(options, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => resolve(body));
    });

    req.on('error', reject);
    req.end();
  });

  return JSON.parse(data);
}
