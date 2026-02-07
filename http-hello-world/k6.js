import http from "k6/http";
import {check} from "k6";

export const options = {
    scenarios: {
        blast: {
            executor: "ramping-arrival-rate",
            timeUnit: "1s",
            startRate: 1000,
            stages: [
                {duration: "10s", target: 5000},
                {duration: "30s", target: 5000},
                {duration: "10s", target: 10000},
                {duration: "20s", target: 10000},
                {duration: "10s", target: 1000},
            ],
            preAllocatedVUs: 2000,
            maxVUs: 5000,
        },
    },
    thresholds: {
        http_req_duration: ["p(95)<100", "p(99)<300"],
        http_req_failed: ["rate<0.01"],
    },
};

const BASE = __ENV.BASE_URL || "http://localhost:8080";

export default function () {
    var res = http.get(BASE + "/hello");

    check(res, {
        "status 200": function (r) {
            return r.status === 200;
        },
        "has message": function (r) {
            return r.json().message === "hello world";
        },
    });
}

export function handleSummary(data) {
    var reqs = data.metrics.http_reqs.values.count;
    var rate = data.metrics.http_reqs.values.rate;
    var fails = data.metrics.http_req_failed.values.passes;
    var med = data.metrics.http_req_duration.values.med;
    var p95 = data.metrics.http_req_duration.values["p(95)"];
    var p99 = data.metrics.http_req_duration.values["p(99)"];

    console.log("\n=== Hello World Load Test ===");
    console.log("Total requests:  " + reqs);
    console.log("Avg RPS:         " + rate.toFixed(0));
    console.log("Failed:          " + fails);
    console.log("Median:          " + med.toFixed(2) + "ms");
    console.log("p95:             " + p95.toFixed(2) + "ms");
    console.log("p99:             " + p99.toFixed(2) + "ms");

    return {};
}
