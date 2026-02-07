<?php

class UserController {
    public function index() {
        $service = new UserService();
        $users = $service->getAllUsers();
        return jsonResponse($users);
    }

    public function store() {
        $service = new UserService();
        $data = parseRequest('POST /users');
        $user = $service->createUser($data);
        return jsonResponse($user, 201);
    }

    public function show($id) {
        $service = new UserService();
        $user = $service->findUser($id);
        if (!$user) {
            return errorResponse('User not found', 404);
        }
        return jsonResponse($user);
    }
}
