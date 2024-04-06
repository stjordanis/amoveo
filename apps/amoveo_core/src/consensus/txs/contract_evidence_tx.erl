-module(contract_evidence_tx).
-export([go/4, make_dict/6, make_tree/1, make_proof1/1, make_proof/2, serialize_row/2, run/5,
        all_lengths/2, sum_vector/2, column_sum/2,make_tree/1]).
-include("../../records.hrl").

make_dict(From, Contract, CID, Evidence, Prove, Fee) ->
    A = trees:get(accounts, From),
    Nonce = A#acc.nonce + 1,
    #contract_evidence_tx{from = From, nonce = Nonce, fee = Fee, contract = Contract, evidence = Evidence, prove = Prove, contract_id = CID}.
    
go(Tx, Dict, NewHeight, NonceCheck) ->
    #contract_evidence_tx{
    from = From,
    nonce = Nonce0,
    fee = Fee,
    contract = ContractBytecode,
    contract_id = CID,
    evidence = Evidence,%like the script sig in bitcoin
    prove = Prove%on-chain state to include.
   } = Tx,
%    Nonce = if 
%                 NonceCheck -> Nonce0;
%                 true -> none
%             end,
    Nonce = nonce_check:doit(
              NonceCheck, 
              Tx#contract_evidence_tx.nonce),
    Facc = accounts:dict_update(From, Dict, -Fee, Nonce),
    Dict2 = accounts:dict_write(Facc, Dict),
    Contract = contracts:dict_get(CID, Dict2),
    #contract{
      many_types = Many,
      nonce = ContractNonce,
      last_modified = LM,
      delay = Delay,
      closed = 0,
      result = Result,
      source = Source,
      source_type = SourceType,
      volume = Volume
     } = Contract,
    CH = hash:doit(ContractBytecode),
    CID = contracts:make_id(CH, Many,Source,SourceType),%verify that this is the correct code for this contract.
    case run(NewHeight, Prove, Evidence, ContractBytecode, Dict2) of
        {error, Error} ->
            io:fwrite("\n in contract_evidence_tx, contract has an error\n"),
            io:fwrite(Error),
            io:fwrite("\n"),
            io:fwrite("block height: "),
            io:fwrite(integer_to_list(NewHeight)),
            io:fwrite("\n"),
            %io:fwrite(packer:pack([Prove, Evidence, ContractBytecode])),
            %io:fwrite("\n"),
            Dict2;
        Data2 ->
            case chalang:stack(Data2) of
                [<<CNonce:32>>,<<CDelay:32>>,PayoutVector|_] when (is_list(PayoutVector)) ->
                    %the source currency is divided up between the subcurrencies according to a payout vector.
                    B1 = CNonce > ContractNonce,
                    B2 = (Many == length(PayoutVector)),
                    TwoE32 = 4294967295,%(2**32 - 1) highest expressible value in chalang integers. payout quantities need to sum to this.
                    B3 = sum_vector(TwoE32, PayoutVector),
                    B4 = B1 and B2 and B3,
                    if
                        not(B4) ->
                            if
                                not(B1) -> io:fwrite("resolve contract tx, vector case, nonce is too low to update\n");
                                not(B2) -> 
                                    io:fwrite(packer:pack([Many, PayoutVector])),
                                    io:fwrite("resove_contract_tx, payout vector is the wrong length\n");
                                not(B3) -> 
                                    io:fwrite(packer:pack(PayoutVector)),
                                    io:fwrite("\ncontract_evidence_tx, payout vector doesn't conserve the total quantity of veo.\n")
                            end,
                            Dict2;
                        true ->
                            Contract2 = Contract#contract{
                                          result = hash:doit(serialize_row(PayoutVector, <<>>)),
                                          nonce = CNonce,
                                          delay = CDelay,
                                          last_modified = NewHeight
                                         },
                            contracts:dict_write(Contract2, Dict2)
                    end;
                [<<CNonce:32>>,<<CDelay:32>>,<<ResultCH:256>>,Matrix|_] ->
                    %contract is being converted into a different contract defined by ResultCH and the length of rows in the matrix.
                    %for every subcurrency type in the original contract, we need to specify a rule for how many of which kinds of subcurrency they will receive in the new contract. We use a matrix for this. Each row is for one original subcurrency.
                    B1 = CNonce > ContractNonce,
                    B2 = is_list(Matrix),
                    B3 = (Many == length(Matrix)),
                    RMany = length(hd(Matrix)),
                    B4 = all_lengths(RMany, Matrix),
                    TwoE32 = 4294967295,%(2**32 - 1) highest expressible value in chalang integers.
                    B5 = column_sum(TwoE32, Matrix),
                    MCF = governance:dict_get_value(max_contract_flavors, Dict, NewHeight),
                    B7 = RMany =< MCF,
                    B6 = B1 and B2 and B3 and B4 and B5 and B7,
                    if
                        not(B6) ->
                            if
                                not(B1) -> io:fwrite("resolve contract tx, nonce is too low to update contract.\n");
                                not(B2) -> io:fwrite("contract_evidence_tx, matrix is misformatted.\n");
                                not(B3) -> io:fwrite("contract_evidence_tx, matrix has wrong number of rows.\n");
                                not(B4) -> io:fwrite("contract_evidence_tx, matrix has a row with the wrong length.\n");
                                not(B5) -> io:fwrite("contract_evidence_tx, matrix does not conserve the total number of veo.\n");
                                not(B7) -> io:fwrite("contract_evidence_tx, matrix rows are too long. we can't have a contract with that many subcurrencies.\n")
                            end,
                            Dict2;
                        true ->
                   
                            RCID = contracts:make_id(<<ResultCH:256>>, RMany,Source,SourceType),

                            {MRoot, M2} = make_tree(Matrix), 
                            RootHash = mtree:root_hash(MRoot, M2),
                            Contract2 = Contract#contract{
                                          result = RootHash,
                                          nonce = CNonce,
                                          delay = CDelay,
                                          sink = RCID,
                                          last_modified = NewHeight
                                         },
                            contracts:dict_write(Contract2, Dict2)
                    end;
                Output ->
                    io:fwrite("in contract_evidence_tx, contract has invalid output\n"),
                    io:fwrite(packer:pack(Output)),
                    io:fwrite("\n"),
                    io:fwrite("block height: "),
                    io:fwrite(integer_to_list(NewHeight)),
                    io:fwrite("\n"),
                    Dict2
            end
    end.
    
all_lengths(_, []) -> true;
all_lengths(L, [H|T]) -> 
    B1 = is_list(H),
    B2 = (L == length(H)),
    if
        (B1 and B2) -> all_lengths(L, T);
        true -> false
    end.

column_sum(_, [[]|_]) -> true;
column_sum(N, M) -> 
    B = (N == column_sum2(0, M)),
    M2 = tails(M),
    B and column_sum(N, M2).
column_sum2(N, []) -> N;
column_sum2(N, [[<<H:32>>|_]|R]) ->
    column_sum2(H+N, R).
tails([]) -> [];
tails([H|T]) -> 
    [tl(H)|tails(T)].


serialize_row([], B) -> B;
serialize_row([<<H:32>>|T], A) -> 
    A2 = <<A/binary, H:32>>,
    R = serialize_row(T, A2).

run(NewHeight, Prove, Evidence, ContractBytecode, Dict2) ->
    true = chalang:none_of(Evidence),
    Funs = governance:dict_get_value(
             fun_limit, Dict2, NewHeight),
    Vars = governance:dict_get_value(
             var_limit, Dict2, NewHeight),
    OpGas = governance:dict_get_value(
              time_gas, Dict2, NewHeight),
    RamGas = governance:dict_get_value(
               space_gas, Dict2, NewHeight),

    State = chalang:new_state(NewHeight, 0, 0),
    ProveCode = spk:prove_facts(Prove, Dict2, NewHeight),
    %io:fwrite("proved facts \n"),
    %io:fwrite(base64:encode(ProveCode)),
    %io:fwrite("\n"),
    AllCode = <<Evidence/binary, ProveCode/binary, ContractBytecode/binary>>,
    Data = chalang:data_maker(OpGas, RamGas, Vars, Funs, <<>>, AllCode, State, constants:hash_size(), 2, false),
    chalang:run5(AllCode, Data).
    
sum_vector(0, []) -> true;
sum_vector(X, []) -> 
    io:fwrite("contract evidence tx, bad vector sum by \n"),
    io:fwrite(packer:pack(X)),
    io:fwrite("\n"),
    false;
sum_vector(N, [<<X:32>>|T]) when (N >= 0)-> 
    sum_vector(N - X, T);
sum_vector(N, L) -> 
    io:fwrite("contract evidence tx, weird vector sum error \n"),
    io:fwrite(packer:pack([N, L])),
    io:fwrite("\n"),
    false.



make_leaves(Matrix, MT) ->
    CFG = mtree:cfg(MT),
    %L1 =  leaf:new(0, CH, 0, CFG),
    make_leaves2([], 1, Matrix, CFG).
make_leaves2(X, _, [], _) -> X;
make_leaves2(X, N, [R|T], CFG) -> 
    SR = serialize_row(R, <<>>),
    RH = hash:doit(SR),
    L = leaf:new(N, RH, 0, CFG),
    make_leaves2([L|X], N+1, T, CFG).
make_tree(Matrix) ->
    MT = mtree:new_empty(5, 32, 0),
    Leaves = make_leaves(Matrix, MT),
    mtree:store_batch(Leaves, 1, MT).
make_proof(N, Matrix) ->
    {Root, MT} = make_tree(Matrix), 
    true = (N =< MT),
    CFG = mtree:cfg(MT),
    {MP_R, Leaf1, Proof1} = 
        mtree:get(leaf:path_maker(N, CFG),
                  Root,
                  MT),
    {MP_R, leaf:value(Leaf1), Proof1}.
make_proof1(Matrix) ->
    make_proof(1, Matrix).
%    {Root, MT} = make_tree(Matrix), 
%    CFG = mtree:cfg(MT),
%    {MP_R, Leaf1, Proof1} = 
%        mtree:get(leaf:path_maker(1, CFG),
%                  Root,
%                  MT),
%    {MP_R, leaf:value(Leaf1), Proof1}.
    
    
