<?php

class ProductController {
    public function list() {
        $service = new ProductService();
        $products = $service->getAllProducts();
        return jsonResponse($products);
    }

    public function create() {
        $service = new ProductService();
        $data = parseRequest('POST /products');
        $product = $service->createProduct($data);
        return jsonResponse($product, 201);
    }

    public function details($id) {
        $service = new ProductService();
        $product = $service->findProduct($id);
        if (!$product) {
            return errorResponse('Product not found', 404);
        }
        return jsonResponse($product);
    }
}
