;defining global variables
(var c_pubkey
     c_period
     c_market_id
     c_max_price
     c_expires
     c_height)
(var i_max_price)


(define (die)
  (return 9999999 0 0))
(define (require b)
  (cond (b ())
        (true (die))))

(define (helper pdv) ;given the full oracle data provided by the blockchain, produce the integer result of that oracle. There are 4 possible outputs: 0,1,2, or 3. 0 means it is still open. 1 means true. 2 means false. 3 means it was a bad question.
  (let (((version pd0) (car@ pdv))
        ((MarketID2 pd) ((require (= 5 version))
                         (car@ pd0)))
        (pd2 ((require (= MarketID2 (@ c_market_id)))
             (car pd)))
        ((T _) (split pd2 32))
        ((_ Result) (split T 1))
        )
    (++ --AAAA Result)));switch from 1 byte binary to a integer representation.

(define (extract signed_price_declaration)
  (let (((sig data) (split signed_price_declaration 40))
        ((R0 DeclaredHeight) ((split data 4)))
        ((R DeclaredPrice0) ((split R0 2)))
        (DeclaredPrice (++ --AAA= DeclaredPrice0))
        ((MarketID2 PortionMatched0) (split R 2))
        (PortionMatched ((++ --AAA= PortionMatched0)))
        )
    (
     (require (verify_sig sig data (@ c_pubkey)))
     (require (= (@ c_market_id) MarketID2))
     (require (not (< DeclaredHeight (@ c_height))))
     DeclaredHeight DeclaredPrice PortionMatched
     )))
(define (price_range F)
  (/ (* 10000 F)
     (+ (@ c_max_price) 10000)))
(define (abs a)
  (cond ((< a 0) (- 0 a))
        (true a)))
(define (minus_zero a b)
  (cond ((> a b) (- a b))
        (true 0)))
(define (bet oracle_result Direction)
  ((cond ((= oracle_result 0)
          (require (> height
                      (@ c_expires))))
         (true (forth 0 drop)))
   (cond ((= Direction oracle_result) 10000)
         ((and (> oracle_result 0)
               (< oracle_result 3))
          0)
         (true (@ i_max_price)))))
(define (evidence)
  (let ((spd ())
        ((DeclaredHeight _ PortionMatched) (extract spd)))
    ((require (> DeclaredHeight (- height (@ c_period))))
     (return (- (@ c_expires) height);delay
             (+ 1 (/ DeclaredHeight (@ c_period)));nonce
             (price_range (@ i_max_price));amount
             ))))
(define (contradictory_prices)
  (let (((spd1 spd2) ())
        ((h1 p1 pm1) (extract spd1))
        ((h2 p2 pm2) (extract spd2)))
    ((require (< (abs (- h1 h2))
                 (/ (@ c_period) 2)))
     (require (or (not (= p1 p2))
                  (not (= pm1 pm2))))
     (return 0 2000000 0))))
(define (match_order OracleData Direction)
  (let (((spd) ())
        ((h p0 pm) (extract spd))
        (p (cond ((= Direction 2) (- 10000 p0))
                 (true p0)))
        (oracle_result (helper OracleData))
        (expired (> height (@ c_expires)))
        (nonce 
         (+ (minus_zero (@ c_expires) h)
            (cond (oracle_result 3)
                  (expired 3)
                  (true 1))))
        (delay (cond (oracle_result 0)
                     (expired 0)
                      (true (+ (@ c_expires)
                               (minus_zero (@ c_expires)
                                           height)))))
        (amount (bet oracle_result Direction))
        (amount2 (cond ((and (= oracle_result 0)
                             expired)
                        (@ i_max_price))
                       ((= (@ c_max_price) p)
                        (/ (+ (* pm amount)
                              (* (@ i_max_price)
                                 (- 10000 pm)))
                           10000))
                       (true
                        (+ amount
                           (- (@ c_max_price)
                               p))))))
    (return delay nonce (price_range amount2))))
(define (unmatched oracle_data)
  (cond ((= 0 (helper oracle_data))
          (return (+ 2000 (+ (@ c_expires) (@ c_period)))
                  0
                  (price_range (@ i_max_price))))
         (true (return (@ c_period) 1 (price_range (@ i_max_price))))))
(define (no_publish)
  (return (@ c_period) (/ height (@ c_period)) 0))

(forth c_pubkey !
       c_period !
       c_market_id !
       c_max_price !
       c_expires !
       c_height ! )
(let (
      ((mode OracleData0 Direction) ())
      (OracleData (car OracleData0))
      )
  (
   (set! i_max_price (- 10000 (@ c_max_price)))
   (case mode
    (1 (match_order OracleData Direction))
    (4 (unmatched OracleData))
    (0 (no_publish))
    (2 (contradictory_prices))
    (3 (evidence))
    (else (die)))))

