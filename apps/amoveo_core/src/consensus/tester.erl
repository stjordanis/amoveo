-module(tester).
-export([test/0, test_helper/1, encryption_test/0]).
test() ->
    case keys:status() of
	unlocked -> test1();
	_ -> "you need to unlock with keys:unlock(""password"") first"
    end.
test_helper([]) -> success;
test_helper([A|B]) ->
    io:fwrite(atom_to_list(A) ++ " test\n"),
    success = A:test(),
    headers:dump(),
    block:initialize_chain(),
    tx_pool:dump(),
    test_helper(B).
test1() ->
    %timer:sleep(2000),
    S = success,
    headers:dump(),
    block:initialize_chain(),
    tx_pool:dump(),
    Tests = [secrets, db, signing, packer, tree_test, block_hashes, block, spk, test_txs, existence, %order_book, 
proofs], %, lisp_market2, lisp_scalar], %headers, keys],
    S = test_helper(Tests).

    
encryption_test() ->
    %EM=encryption:send_msg(Message, base64:encode(Pubkey), base64:encode(R#f.pub), base64:encode(R#f.priv)),
    Pub1_64 = "BNFsD42eXjwHd4PyP4lODu+aybYjmVJF0bA0UYNcJ2/cELBl5Z6IA639jUl1km+8YAD3aL3of+SqLI8emuhsa2c=",
    Priv1_64 = "wruxx99+2hK4cT+j1SkJhV6VzBxgbl11iHxnq6ghASA=",
    Pub2_64 = "BA7HtKYPIvUwQjmUqNQ0UMsxHu+KtISveg45Jl+tl/y6OMgtyC3rE4/YrEHLtTprCPsxcus5CbhmlWo9IDKfnzo=",
    Priv2_64 = "4a6E2IK3hhhP2dK8xGYaUqg23Fk/n/Ms2VuORKC5Xvo=",
    EM = encryption:send_msg([1,2,3], Pub2_64, Pub1_64, Priv1_64),%msg, to, from
    io:fwrite("encryption_test\n"),
    io:fwrite(packer:pack(EM)),
    ok.
    
