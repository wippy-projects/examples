<?php

function jsonResponse($data, $status = 200) {
    $body = formatJson($data);
    return sendResponse($body, $status, 'application/json');
}

function formatJson($data) {
    return json_encode($data);
}

function sendResponse($body, $status, $contentType) {
    return ['status' => $status, 'content_type' => $contentType, 'body' => $body];
}

function errorResponse($message, $code = 500) {
    return jsonResponse(['error' => $message], $code);
}
