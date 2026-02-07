import http from "k6/http";
import {check} from "k6";
import {Counter, Trend} from "k6/metrics";

const tasksQueued = new Counter("tasks_queued");
const submitLatency = new Trend("submit_latency");
const listLatency = new Trend("list_latency");

export const options = {
    scenarios: {
        // High-throughput task submission — targets 5000 rps
        blast: {
            executor: "ramping-arrival-rate",
            timeUnit: "1s",
            startRate: 1000,
            stages: [
                {duration: "10s", target: 10000},
                {duration: "10s", target: 100000},
                {duration: "10s", target: 1000},
            ],
            preAllocatedVUs: 5000,
            maxVUs: 10000,
        },
        // Steady reader polling results
        readers: {
            executor: "constant-arrival-rate",
            rate: 100,
            timeUnit: "1s",
            duration: "30s",
            preAllocatedVUs: 5000,
            maxVUs: 10000,
            exec: "listTasks",
        },
    },
    thresholds: {
        http_req_duration: ["p(95)<500", "p(99)<1000"],
        http_req_failed: ["rate<0.01"],
        submit_latency: ["p(95)<300"],
        list_latency: ["p(95)<500"],
    },
};

const BASE = __ENV.BASE_URL || "http://localhost:8080";
const params = {headers: {"Content-Type": "application/json"}};

const PAYLOADS = [
    JSON.stringify({action: "uppercase", data: {text: "hello world"}}),
    JSON.stringify({action: "uppercase", data: {text: "load test message"}}),
    JSON.stringify({action: "uppercase", data: {text: "stress the queue"}}),
    JSON.stringify({action: "sum", data: {numbers: [1, 2, 3, 4, 5]}}),
    JSON.stringify({action: "sum", data: {numbers: [10, 20, 30, 40, 50]}}),
    JSON.stringify({action: "cleanup", data: {target: "/tmp"}}),
    JSON.stringify({action: "report", data: {}}),
    JSON.stringify({action: "index", data: {collection: "users"}}),
];

// Default scenario: blast task submissions
export default function () {
    var payload = PAYLOADS[Math.floor(Math.random() * PAYLOADS.length)];
    var res = http.post(BASE + "/tasks", payload, params);

    submitLatency.add(res.timings.duration);

    var ok = check(res, {
        "queued (202)": function (r) {
            return r.status === 202;
        },
    });

    if (ok) {
        tasksQueued.add(1);
    }
}

// Reader scenario: poll task list
export function listTasks() {
    var filter = Math.random() > 0.5 ? "?status=completed" : "";
    var res = http.get(BASE + "/tasks" + filter);

    listLatency.add(res.timings.duration);

    check(res, {
        "list ok (200)": function (r) {
            return r.status === 200;
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
    var queued = data.metrics.tasks_queued ? data.metrics.tasks_queued.values.count : 0;

    console.log("\n=== Task Queue Load Test ===");
    console.log("Total requests:  " + reqs);
    console.log("Avg RPS:         " + rate.toFixed(0));
    console.log("Tasks queued:    " + queued);
    console.log("Failed:          " + fails);
    console.log("Median:          " + med.toFixed(2) + "ms");
    console.log("p95:             " + p95.toFixed(2) + "ms");
    console.log("p99:             " + p99.toFixed(2) + "ms");

    return {};
}
