import http from "k6/http";
import {check, sleep} from "k6";
import {Counter, Trend} from "k6/metrics";

const tasksAccepted = new Counter("tasks_accepted");
const responseTime = new Trend("task_response_time");

export const options = {
    scenarios: {
        blast: {
            executor: "ramping-arrival-rate",
            timeUnit: "1s",
            startRate: 1000,
            stages: [
                {duration: "10s", target: 10000},
                {duration: "10s", target: 50000},
                {duration: "20s", target: 100000},
                {duration: "30s", target: 100000},
                {duration: "10s", target: 1000},
            ],
            preAllocatedVUs: 5000,
            maxVUs: 10000,
        },
    },

    thresholds: {
        http_req_duration: ["p(95)<500", "p(99)<1000"],
        http_req_failed: ["rate<0.01"],
    },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

const TASK_NAMES = [
    "generate-report",
    "process-data",
    "send-notifications",
    "sync-inventory",
    "analyze-logs",
    "build-index",
    "compress-assets",
    "run-migration",
];

function randomTask() {
    return {
        name: TASK_NAMES[Math.floor(Math.random() * TASK_NAMES.length)],
        duration: Math.floor(Math.random() * 5) + 1,
    };
}

export default function () {
    const payload = JSON.stringify(randomTask());

    const res = http.post(`${BASE_URL}/api/tasks`, payload, {
        headers: {"Content-Type": "application/json"},
    });

    responseTime.add(res.timings.duration);

    check(res, {
        "status is 202": (r) => r.status === 202,
    });

    if (res.status === 202) {
        tasksAccepted.add(1);
    }

    sleep(0.1);
}

export function handleSummary(data) {
    const med = data.metrics.http_req_duration.values.med;
    const p95 = data.metrics.http_req_duration.values["p(95)"];
    const p99 = data.metrics.http_req_duration.values["p(99)"];
    const reqs = data.metrics.http_reqs.values.count;
    const fails = data.metrics.http_req_failed.values.passes;

    console.log("\n=== Results ===");
    console.log(`Requests:  ${reqs}`);
    console.log(`Failed:    ${fails}`);
    console.log(`Median:    ${med.toFixed(2)}ms`);
    console.log(`p95:       ${p95.toFixed(2)}ms`);
    console.log(`p99:       ${p99.toFixed(2)}ms`);

    return {};
}
