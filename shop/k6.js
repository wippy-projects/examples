import http from "k6/http";
import {check, sleep, group} from "k6";
import {Counter} from "k6/metrics";

var checkouts = new Counter("checkouts_completed");

export var options = {
    scenarios: {
        shoppers: {
            executor: "ramping-vus",
            startVUs: 1,
            stages: [
                {duration: "10s", target: 5},
                {duration: "30s", target: 5},
                {duration: "10s", target: 0},
            ],
            gracefulStop: "10s",
        },
    },
    thresholds: {
        http_req_duration: ["p(95)<500"],
        http_req_failed: ["rate<0.05"],
    },
};

var BASE = __ENV.BASE_URL || "http://localhost:8080";
var SKUS = ["LAPTOP-001", "KB-002", "MOUSE-003", "MON-004", "HP-005"];

function pickRandom(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
}

export default function () {
    var userId = "user_" + __VU + "_" + __ITER;
    var params = {headers: {"Content-Type": "application/json"}};

    // 1. Browse products
    group("browse products", function () {
        var res = http.get(BASE + "/api/products");
        check(res, {
            "products listed": function (r) {
                return r.status === 200;
            },
        });
        sleep(0.5);
    });

    // 2. Add 1-3 random items to cart
    group("add items to cart", function () {
        var count = Math.floor(Math.random() * 3) + 1;
        for (var i = 0; i < count; i++) {
            var body = JSON.stringify({
                sku: pickRandom(SKUS),
                quantity: Math.floor(Math.random() * 2) + 1,
            });
            var res = http.post(BASE + "/api/cart/" + userId + "/items", body, params);
            check(res, {
                "item added": function (r) {
                    return r.status === 200;
                },
            });
            sleep(0.3);
        }
    });

    // 3. View cart
    group("view cart", function () {
        var res = http.get(BASE + "/api/cart/" + userId);
        check(res, {
            "cart retrieved": function (r) {
                return r.status === 200;
            },
        });
        sleep(0.5);
    });

    // 4. Checkout
    group("checkout", function () {
        var res = http.post(BASE + "/api/cart/" + userId + "/checkout", null, params);
        var ok = check(res, {
            "checkout ok": function (r) {
                return r.status === 200;
            },
        });
        if (ok) {
            checkouts.add(1);
        }
        sleep(0.5);
    });

    // Pause between shopping sessions
    sleep(1);
}
