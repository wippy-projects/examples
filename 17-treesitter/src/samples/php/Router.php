<?php

function route($path, $method) {
    if ($path === '/users') {
        return handleUsers($method);
    }
    if ($path === '/products') {
        return handleProducts($method);
    }
    return notFound();
}

function handleUsers($method) {
    $controller = new UserController();
    if ($method === 'GET') {
        return $controller->index();
    }
    return $controller->store();
}

function handleProducts($method) {
    $controller = new ProductController();
    if ($method === 'GET') {
        return $controller->list();
    }
    return $controller->create();
}

function notFound() {
    return errorResponse('Not Found', 404);
}
