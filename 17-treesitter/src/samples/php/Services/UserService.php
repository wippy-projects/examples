<?php

class UserService {
    public function getAllUsers() {
        $model = new UserModel();
        $users = $model->findAll();
        return formatUsers($users);
    }

    public function createUser($data) {
        $validated = validateUserData($data);
        $model = new UserModel();
        return $model->insert($validated);
    }

    public function findUser($id) {
        $model = new UserModel();
        return $model->findById($id);
    }
}

function formatUsers($users) {
    return array_map(function($u) { return $u; }, $users);
}

function validateUserData($data) {
    return $data;
}
