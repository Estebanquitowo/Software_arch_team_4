import http from 'k6/http';
import { check } from 'k6';

const TARGET_URL = __ENV.TARGET_URL || 'http://app.localhost/reports/top_selling_books';
const TOTAL_REQUESTS = parseInt(__ENV.REQUESTS || '100', 10);

export const options = {
  insecureSkipTLSVerify: true,
  iterations: TOTAL_REQUESTS,
  vus: Math.min(TOTAL_REQUESTS, 50),
  maxDuration: '5m',
};

export default function () {
  const res = http.get(TARGET_URL);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}
