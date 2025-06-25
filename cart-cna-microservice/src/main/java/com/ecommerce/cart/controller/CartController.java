package com.ecommerce.cart.controller;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.ReactiveRedisTemplate;
import org.springframework.data.redis.core.ReactiveValueOperations;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ecommerce.cart.model.Cart;
import com.ecommerce.cart.model.CartItem;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@CrossOrigin
@RestController
public class CartController {

    private static final Logger LOG = LoggerFactory.getLogger(CartController.class);

    private ReactiveRedisTemplate<String, Cart> redisTemplate;

    private ReactiveValueOperations<String, Cart> cartOps;

    CartController(ReactiveRedisTemplate<String, Cart> redisTemplate) {
        this.redisTemplate = redisTemplate;
        this.cartOps = this.redisTemplate.opsForValue();
    }

    @RequestMapping("/")
    public String index() {
        return "{ \"name\": \"Cart API\", \"version\": 1.0.0} ";
    }

    @GetMapping("/cart")
    public Flux<Cart> list() {
        return redisTemplate.keys("*")
                .flatMap(cartOps::get);
    }

    @GetMapping("/cart/{customerId}")
    public Mono<Cart> findById(@PathVariable String customerId) {
        return cartOps.get(customerId);
    }

    @PostMapping("/cart")
    Mono<Void> create(@RequestBody Mono<Cart> cart) {
        return cart.doOnNext(c -> {
            LOG.info("Adding cart to Redis: {}", c);
            float total = 0;
            if (c.getCustomerId() == null) {
                LOG.error("Customer Id is missing.");
                return;
            }
            for (CartItem item : c.getItems()) {
                total += item.getPrice() * item.getQuantity();
            }
            c.setTotal(total);
            cartOps.set(c.getCustomerId(), c).subscribe();
        }).then();
    }
    
    @PostMapping("/cart/{customerId}/items")
    @Timed(name = "cart.add_item", description = "Time taken to add item to cart")
    @NewSpan("add-cart-item")
    public Mono<Cart> addItem(@SpanTag("customerId") @PathVariable String customerId, 
                             @RequestBody CartItem item) {
        MDC.put("customerId", customerId);
        LOG.info("Adding item to cart for customer: {}, product: {}", customerId, item.getProductId());
        cartCounter.increment("operation", "add_item");
        
        return findById(customerId)
            .flatMap(cart -> {
                cart.addItem(item);
                return createOrUpdate(Mono.just(cart));
            })
            .doFinally(signal -> MDC.clear());
    }
    
    @DeleteMapping("/cart/{customerId}/items/{productId}")
    @Timed(name = "cart.remove_item", description = "Time taken to remove item from cart")
    @NewSpan("remove-cart-item")
    public Mono<Cart> removeItem(@SpanTag("customerId") @PathVariable String customerId,
                                @SpanTag("productId") @PathVariable String productId) {
        MDC.put("customerId", customerId);
        MDC.put("productId", productId);
        LOG.info("Removing item from cart for customer: {}, product: {}", customerId, productId);
        cartCounter.increment("operation", "remove_item");
        
        return findById(customerId)
            .flatMap(cart -> {
                cart.removeItem(productId);
                return createOrUpdate(Mono.just(cart));
            })
            .doFinally(signal -> MDC.clear());
    }
}