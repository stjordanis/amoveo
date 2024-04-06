-module(market_swap_tx).
-export([go/4, make_dict/6, make_dict/10]).
-include("../../records.hrl").

make_dict(From, MID, Give, Take, Direction, Fee, CID10, Type10, CID20, Type20) ->
    <<N1:256>> = CID10,
    <<N2:256>> = CID20,
    {CID1, Type1,
     CID2, Type2} = 
        if
            ((N1+Type10) =< (N2+Type20)) ->
                {CID10, Type10,
                 CID20, Type20};
            true ->
                {CID20, Type20,
                 CID10, Type10}
        end,
    Acc = trees:get(accounts, From),
    #market_swap_tx{
                 from = From,
                 nonce = Acc#acc.nonce + 1,
                 mid = MID,
                 cid1 = CID1,
                 type1 = Type1,
                 cid2 = CID2,
                 type2 = Type2,
                 fee = Fee,
                 give = Give,
                 take = Take,
                 direction = Direction}.
make_dict(From, MID, Give, Take, Direction, Fee) ->
    Acc = trees:get(accounts, From),
    Market = trees:get(markets, MID),
    #market{
             cid1 = CID1,
             type1 = Type1,
             cid2 = CID2,
             type2 = Type2
           } = Market,
    make_dict(From, MID, Give, Take, Direction, Fee, CID1, Type1, CID2, Type2).
go(Tx, Dict, NewHeight, NonceCheck) ->
    #market_swap_tx{
    from = From,
    nonce = Nonce,
    mid = MID,
    cid1 = CID1,
    type1 = Type1,
    cid2 = CID2,
    type2 = Type2,
    fee = Fee,
    give = Give0,
    take = Take,
    direction = Direction
   } = Tx,
    F41 = forks:get(41),
    F43 = forks:get(43),
    Give = if
               (NewHeight > F41) and
               (NewHeight < F43) ->
                   GiveLimit = 
                       case Direction of
                           1 -> balance(From, CID1, Type1, Dict);
                           2 -> balance(From, CID2, Type2, Dict)
                       end,
                   BalanceBeforeFlashLoan = GiveLimit - Give0,
                   min(Give0, BalanceBeforeFlashLoan);
               true -> Give0
           end,
%    Nonce2 = 
%        if
%            (NonceCheck and (NewHeight > F41)) -> Nonce;
%            true -> none
%        end,
    Nonce2 = 
        if (NewHeight > F41) ->
                nonce_check:doit(
                  NonceCheck, 
                  Tx#market_swap_tx.nonce);
           true -> none
        end,
    Facc = accounts:dict_update(From, Dict, -Fee, Nonce2),
    Dict2 = accounts:dict_write(Facc, Dict),
    M = markets:dict_get(MID, Dict2),
    #market{
             cid1 = CID1,
             type1 = Type1,
             cid2 = CID2,
             type2 = Type2,
             amount1 = Amount1,
             amount2 = Amount2,
             shares = Shares
           } = M,
    {D1, D2} = %D1 is how many cid1 coins Pub gets.
        case Direction of
            1 -> 
                %maintain constant product in the market.
                %A1*A2 = (A1 + give)*(A2 - get)
                %(A2 - get) = (A1*A2)/(A1 + give)
                Get = Amount2 - (Amount1 * Amount2 div (Amount1 + Give)),
                if
                    (Get > Take) ->
                        ok;
                    true ->
                        %io:fwrite("market swap failure, not enough to take \n"),
                        %io:fwrite(packer:pack([Get, Take])),
                        %io:fwrite("\n"),
                        1 = 1+1
                end,
                %true = Get > Take,
                {-Give, Get};
            2 -> 
                Get = Amount1 - (Amount2 * Amount1 div (Amount2 + Give)),
                if
                    (Get > Take) ->
                        ok;
                    true ->
                        %io:fwrite("market swap failure, not enough to take \n"),
                        %io:fwrite(packer:pack([Get, Take])),
                        %io:fwrite("\n"),
                        1 = 1+1
                end,
                %true = Get > Take,
                {Get, -Give}
        end,
    Gov = governance:dict_get_value(market_trading_fee, Dict2, NewHeight),
    N = 100000000,
    {G1, G2} = 
        if
            D1 > 0 -> 
                X = D1 * (N - Gov) div N,
                {X, D2};
            true ->
                X = D2 * (N - Gov) div N,
                {D1, X}
        end,
    %take away one kind of currency from acc, give to market.
    Dict3 = market_liquidity_tx:send_stuff(From, CID1, Type1, Dict2, G1),
    Dict4 = market_liquidity_tx:send_stuff(From, CID2, Type2, Dict3, G2),
    M2 = M#market{
      amount1 = M#market.amount1 - G1,
      amount2 = M#market.amount2 - G2},
    Dict5 = markets:dict_write(M2, Dict4, NewHeight),
    Dict5.

balance(Pub, <<0:256>>, Type, Dict) ->
    Type = 0,
    Acc = accounts:dict_get(Pub, Dict),
    Acc#acc.balance;
balance(Pub, CID, Type, Dict) ->
    Key = sub_accounts:make_key(Pub, CID, Type),
    SubAcc = sub_accounts:dict_get(Key, Dict),
    SubAcc#sub_acc.balance.

