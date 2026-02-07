<?php

class UserModel {
    public function findAll() {
        $db = Database::connect();
        return $db->query('SELECT * FROM users');
    }

    public function findById($id) {
        $db = Database::connect();
        return $db->query('SELECT * FROM users WHERE id = ?', [$id]);
    }

    public function insert($data) {
        $db = Database::connect();
        return $db->execute('INSERT INTO users (name) VALUES (?)', [$data]);
    }
}
