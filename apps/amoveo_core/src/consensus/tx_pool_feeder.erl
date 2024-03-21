-module(tx_pool_feeder).
-behaviour(gen_server).
-export([start_link/0,init/1,handle_call/3,handle_cast/2,handle_info/2,terminate/2,code_change/3, absorb_dump/2]).
-export([absorb/1, absorb/2, absorb_async/1, is_in/2,
	 absorb_dump2/2, dump/1]).
-include("../records.hrl").
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, ok, []).
init(ok) -> 
    %process_flag(trap_exit, true),
    {ok, []}.
%TODO using a self() inside of this isn't good, because it is already a gen server listening for messages. and the two kinds of messages are interfering.
handle_call({absorb, SignedTx, Timeout}, _From, State) when (is_integer(Timeout) and (Timeout > -1)) ->
    R = absorb_timeout(SignedTx, Timeout),
    {reply, R, State};
handle_call({absorb, SignedTx}, _From, State) ->
    %io:fwrite("tx pool feeder absorb/1\n"),
    R = absorb_internal(SignedTx),
    %io:fwrite("tx pool feeder absorb/1 done\n"),
    {reply, R, State};
handle_call({absorb_dump2, Block, SignedTxs}, _, S) -> 
    tx_pool:dump(Block),
    ai2(SignedTxs),
    {reply, ok, S};
handle_call(_, _, S) -> {reply, S, S}.
handle_cast({dump, Block}, S) -> 
    tx_pool:dump(Block),
    {noreply, S};
handle_cast({absorb, SignedTxs}, S) -> 
    ai2(SignedTxs),
    {noreply, S};
handle_cast({absorb_dump, Block, SignedTxs}, S) -> 
    tx_pool:dump(Block),
    ai2(SignedTxs),
    {noreply, S};
handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.
terminate(_, _) ->
    %ok.
    io:fwrite("tx_pool_feeder died\n").
code_change(_, S, _) -> {ok, S}.
is_in(_, []) -> false;
is_in(Tx, [STx2 | T]) ->
    Tx2 = signing:data(STx2),
    (Tx == Tx2) orelse (is_in(Tx, T)).
absorb_internal(SignedTx) ->
    %io:fwrite("tx pool feeder absorb internal\n"),
    Wait = case application:get_env(amoveo_core, kind) of
	       {ok, "production"} -> 2000;
	       %_ -> 400
	       _ -> 2000
	   end,
    absorb_timeout(SignedTx, Wait).


%a tx costs computation 3 times. 
%1) When it is generated by the light node working together with a full node. 
%2) When the tx gets included in a block, the mining pool can write a note on it.
%3) When full nodes sync that block, they process the tx.

%we want to minimize (3) to increase scalability, so it is better to do computation at step (2) instead of (3) when possible.

%tx_pool_inclusion_note/2 is step (2)
tx_pool_inclusion_note(futarchy_bet_tx, SignedTx0) ->
    Tx = signing:data(SignedTx0),
    #futarchy_bet_tx
        {
          fid = FID,
          limit_price = LP,
          decision = Decision,
          goal = Goal,
          amount = Amount,
          pubkey = Pubkey,
          nonce = Nonce
        } = Tx,
    io:fwrite("0 goal is: "),
    io:fwrite(integer_to_list(Goal)),
    io:fwrite("\n"),
    Futarchy = trees:get(futarchy, FID),
    #futarchy
        {
          true_yes_orders = TYO,
          true_no_orders = TNO,
          false_yes_orders = FYO,
          false_no_orders = FNO,
          shares_true_yes = TYS,
          shares_true_no = TNS,
          shares_false_yes = FYS,
          shares_false_no = FNS,
          liquidity_true = LT,
          liquidity_false = LF
        } = Futarchy,
    {OurOrders, TheirOrders, 
     OurShares, TheirShares, Liquidity} = 
        case {Decision, Goal} of
            {1, 1} -> {TYO, TNO, TYS, TNS, LT};
            {1, 0} -> {TNO, TYO, TNS, TYS, LT};
            {0, 1} -> {FYO, FNO, FYS, FNS, LF};
            {0, 0} -> {FNO, FYO, FNS, FYS, LF}
        end,
 
    TheirTop = TheirOrders,
   Note = 
        case OurOrders of
            <<0:256>> ->
                io:fwrite("tx_pool_feeder, inclusion futarchy bet2 version 0\n"),
                io:fwrite(TYO == <<0:256>>),
                io:fwrite(" "),
                io:fwrite(TNO == <<0:256>>),
                io:fwrite(" "),
                io:fwrite(FYO == <<0:256>>),
                io:fwrite(" "),
                io:fwrite(FNO == <<0:256>>),
                io:fwrite("\n"),
                inclusion_futarchy_bet2(
                  Pubkey, Nonce, Goal,
                  TheirTop, OurOrders, Amount, OurShares, 
                  TheirShares, LP, Liquidity, []);
            _ ->
                OurTop = trees:get(futarchy_unmatched, OurOrders),
                OurPrice = OurTop#futarchy_unmatched.limit_price,
                if
                    (LP > OurPrice) ->
                io:fwrite("tx_pool_feeder, inclusion futarchy bet2 version lp > \n"),
                        inclusion_futarchy_bet2(
                          Pubkey, Nonce, Goal,
                          TheirTop, OurOrders, Amount, OurShares, 
                          TheirShares, LP, Liquidity, []);
                    true ->
                        {TIDAhead, TIDBehind} = 
                            futarchy_unmatched:id_pair(
                              LP, futarchy_bet_tx:orders(
                                    Decision, Goal, 
                                    Futarchy)),
                        io:fwrite("tx_pool_feeder, inclusion note. your trade is added to the order book\n"),
                        {0, TIDAhead, TIDBehind}
                end
        end,
    setelement(4, SignedTx0, Note);
tx_pool_inclusion_note(_Type, SignedTx0) -> SignedTx0.
   
inclusion_futarchy_bet2(
  Pubkey, Nonce, Goal, <<0:256>>, OurOrders, Amount, OurShares, 
  TheirShares, LimitPrice, B, AccTIDs) -> 
    %when the order id is <<0:256>>, that means there is nothing left to match with.
    io:fwrite("tx pool feeder inclusion futarchy bet 2 case 0\n"),
    QD = lmsr:max_buy(B, TheirShares, OurShares, Amount),
    {QF, QS} = case Goal of
                   1 -> {OurShares + QD, TheirShares};
                   0 -> {TheirShares, OurShares + QD}
               end,
%    io:fwrite({LimitPrice, B, TheirShares}),
        %[{4294967295,288539008,0}],
    Q2 = lmsr:q2({rat, LimitPrice, futarchy_bet_tx:one_square()}, B, TheirShares),
    LMSRProvides = 
        -lmsr:change_in_market(
           B, OurShares, TheirShares,
           Q2, TheirShares),
    if
        LMSRProvides > Amount -> 
            QD = lmsr:max_buy(B, TheirShares, OurShares, Amount),
            TheirSharesA = TheirShares + QD,
            {QFa, QSa} = 
                case Goal of
                    1 -> {OurShares, TheirSharesA};
                    0 -> {TheirSharesA, OurShares}
                end,
            {1, lists:reverse(AccTIDs), <<0:256>>, QFa, QSa};
        [] == AccTIDs -> 
            io:fwrite("tx_pool_feeder, inclusion note: adding a trade to the empty order book\n"),
            {0, <<0:256>>, <<0:256>>};
        true ->
            io:fwrite("tx_pool_feeder, inclusion note. your trade is only partially matched\n"),
%    {1, lists:reverse(AccTIDs), <<0:256>>, QF, QS};
%    FMIDc = futarchy_matched_id_maker(
%              FID, Pubkey, Nonce0),
    %{2, lists:reverse(AccTIDs), [], <<0:256>>, QF, QS};
    %{2, lists:reverse(AccTIDs), [], <<0:256>>, QF, QS};
%            io:fwrite({{before, OurShares, TheirShares}, % 5, 0
%                       {afta, QF, QS},% 5, 13
%                       {others, QD}}),% 13
%            io:fwrite({lists:map(
%                         fun(X) -> trees:get(futarchy_unmatched, X) end, 
%                         AccTIDs)}),
            io:fwrite({AccTIDs}),
            {2, lists:reverse(AccTIDs), <<0:256>>, QF, QS}
    end;
inclusion_futarchy_bet2(
  Pubkey, Nonce, Goal, TheirOrderID, OurOrderID, Amount, OurShares, 
  TheirShares, LimitPrice, B, AccTIDs) -> 
     %walk down their_orders, and see how many trades we can match with, to find out if our order can be completely matched, or if part of it will be left unmatched.
    %use lmsr:q2(P, B, Q1) to see how much extra liquidity we get from the market maker.
    %return the final Q1, Q2, any leftover veo, the list of TID that got matched, and the next tid in the order book.

    %it is possible that price ends up somewhere the market maker is providing liquidity, instead of partially matching a bet, and this can happen either because we hit the price limit, or because we run out of money to trade with.
    io:fwrite("tx pool feeder inclusion futarchy bet 2 case 1\n"),
    Order = trees:get(futarchy_unmatched, TheirOrderID),
%    Order = trees:get(futarchy_unmatched, hd(AccTIDs)),
%    Order = futarchy_unmatched:dict_get(TheirOrderID, Dict),
    #futarchy_unmatched
        {
          id = OID,
          revert_amount = RA,
          limit_price = LP,
          behind = Next,
          futarchy_id = FID,
          goal = Goal2
        } = Order,
    false = Goal2 == Goal,
%    case Goal2 of
%        Goal -> io:fwrite("futarchy bet2 goals match\n");
%        _ -> io:fwrite({{tx, Goal}, {order_book, Goal2}})
%    end,
    %LP should be a rat between 0 and 1.
    Q2 = lmsr:q2({rat, LP, futarchy_bet_tx:one_square()}, B, TheirShares),
    LMSRProvides = 
        lmsr:change_in_market(
          B, OurShares, TheirShares,
          Q2, TheirShares),

    {QF, QS} = case {Goal} of
                   {1} -> {OurShares, Q2};
                   {0} -> {Q2, OurShares}
               end,
    if
        LMSRProvides > Amount ->
           %we ran out of money in the lmsr step
            %we be calculating Q based on available funds to make the purchase, not the limit price.

            QD = lmsr:max_buy(B, TheirShares, OurShares, Amount),
            TheirSharesA = TheirShares + QD,
            {QFa, QSa} = 
                case Goal of
                    1 -> {OurShares, TheirSharesA};
                    0 -> {TheirSharesA, OurShares}
                end,
                        io:fwrite("tx_pool_feeder, inclusion note. your trade is completely matched in the LMSR step\n"),
            {1, lists:reverse(AccTIDs), OID, QFa, QSa};
        true ->
            Amount2 = Amount - LMSRProvides,
            PM = futarchy_bet_tx:prices_match(LimitPrice, LP),
            io:fwrite("tx_pool_feeder, checking if the trades can be matched at thse prices \n"),
            io:fwrite(integer_to_list(LimitPrice)),
            io:fwrite(" "),
            io:fwrite(integer_to_list(LP)),
            io:fwrite(" "),
            io:fwrite(PM),
            io:fwrite(" "),
            io:fwrite(integer_to_list(LP*LimitPrice)),
            io:fwrite(" max: "),
            io:fwrite(integer_to_list(4294967296)),
            io:fwrite("\n"),
            if
                PM ->
                    TradeProvides = RA * futarchy_bet_tx:one() div LP,
                    if
                        (TradeProvides > Amount2) ->
            %we ran out of money matching the trade.
         %will update the trade to be partially matching.
                        io:fwrite("tx_pool_feeder, inclusion note. your trade is completely matched with other trades\n"),
                            {1, lists:reverse(AccTIDs), OID, QF, QS};
                        true ->
            %recurse to the next trade.
                            %NextOrder = trees:get(futarchy_unmatched, Next),
                            inclusion_futarchy_bet2(
                              Pubkey, Nonce, Goal,
                              Next, OurOrderID, Amount2 - TradeProvides,
                              %NextOrder, Amount2 - TradeProvides,
                              Q2, TheirShares, LimitPrice, B, 
                              [OID|AccTIDs])
                    end;
                true ->
                    %todo. We need to handle both of the cases; if the lmsr is or is not providing liquidity.
                   % Q2z = lmsr:max(B, TheirShares, OurShares, Amount),

                    %Q2z = lmsr:q2(LimitPrice, B, TheirShares),
                    QDz = lmsr:max_buy(B, TheirShares, OurShares, Amount),
                    FMID = hash:doit(<<FID/binary, Pubkey/binary, Nonce:32>>),%futarchy matched id.
                    
                    {Q1y, Q2y} = case Goal of
                                     %1 -> {TheirShares, Q2z};
                                     %0 -> {Q2z, TheirShares}
                                     1 -> {OurShares + QDz, TheirShares};
                                     0 -> {TheirShares, OurShares + QDz}
                                 end,
                    case AccTIDs of
                        [] -> 
                            io:fwrite("tx pool feeder, adding a trade to the the order book\n"),
                            {TIDAhead, TIDBehind} = 
                                futarchy_unmatched:id_pair(
                                  LimitPrice, OurOrderID),
                            {0, TIDAhead, TIDBehind};
                        _ ->
                            io:fwrite("add trade to front of order book, and match some orders.\n"),
                            {2, lists:reverse(AccTIDs), TheirOrderID, 
                             Q1y, Q2y}
%                            {1, lists:reverse(AccTIDs), OID, 
%                             Next, FMID, Q1y, Q2y}
                    end
            end
    end.

absorb_timeout(SignedTx0, Wait) ->
    %io:fwrite("tx pool feeder absorb timeout\n"),
    S = self(),
    H = block:height(),
    Tx = signing:data(SignedTx0),
%    F36 = forks:get(36),
%    F38 = forks:get(38),
    SignedTx = tx_pool_inclusion_note(element(1, Tx), SignedTx0),
    %io:fwrite("now 3 "),%1500
    PrevHash = block:hash(headers:top_with_block()),
    spawn(fun() ->
                  absorb_internal2(SignedTx, S)
          end),
    receive
        X when (element(1, X) == dict) -> 
            tx_reserve:add(SignedTx, H),
            tx_pool:absorb_tx(X, SignedTx),
            ok;
        error -> error;
        Y -> {error, Y}
                 
    after 
        Wait -> timeout_error
%            end
    end.
	    
	    
absorb_internal2(SignedTx, PID) ->
    %io:fwrite("now 2 "),%200
    %io:fwrite("absorb internal 2\n"),
    %io:fwrite(packer:pack(now())),
    %io:fwrite("\n"),
    %io:fwrite("tx pool feeder absorb timeout 2\n"),
    Tx = signing:data(SignedTx),
    F = tx_pool:get(),
    Txs = F#tx_pool.txs,
    %io:fwrite("absorb internal 4"),
    case is_in(Tx, Txs) of
        true -> 
            io:fwrite("is in error\n"),
            PID ! error;
        false -> 
	    true = signing:verify(SignedTx),
	    Fee = element(4, Tx),
	    Type = element(1, Tx),

            %io:fwrite("now 3 "),%1500
            %io:fwrite(packer:pack(now())),
            %io:fwrite("\n"),
	    {ok, MinimumTxFee} = application:get_env(amoveo_core, minimum_tx_fee),
	    B = case Type of
                    multi_tx ->
                        MTxs = Tx#multi_tx.txs,
                        Cost = sum_cost(MTxs, F#tx_pool.dict, F#tx_pool.block_trees),
                                                %io:fwrite("now 4 2"),%500
                                                %io:fwrite(packer:pack(now())),
                    %io:fwrite("\n"),
                        MF = MinimumTxFee * length(MTxs),
                        Fee > (MF + Cost);
                    contract_timeout_tx2 ->
                        Fee > MinimumTxFee;
                    _ ->
                        Cost = governance:value(trees:get(governance, Type, F#tx_pool.dict, F#tx_pool.block_trees)),
                                                %io:fwrite("now 4 "),%500
                                                %io:fwrite(packer:pack(now())),
                    %io:fwrite("\n"),
                        Fee > (MinimumTxFee + Cost)
		    %true
                end,
            if
                not(B) -> 
                    io:fwrite("not enough fees"),
                    PID ! error;
                true -> 
                    %io:fwrite("enough fee \n"),
                    %io:fwrite("now 5 "),%2000
                    %io:fwrite(packer:pack(now())),
                    %io:fwrite("\n"),
            %OldDict = proofs:facts_to_dict(F#tx_pool.facts, dict:new()),
                    %io:fwrite("tx pool feeder absorb timeout 2 2\n"),
                    Height = block:height(),
                    {CBTX, _} = coinbase_tx:make(constants:master_pub(), F#tx_pool.block_trees),
                    Txs2 = [SignedTx|Txs],
                    %io:fwrite("tx pool feeder absorb timeout 2 3\n"),
                    Querys = proofs:txs_to_querys([CBTX|Txs2], F#tx_pool.block_trees, Height+1),
                    %io:fwrite("tx pool feeder absorb timeout 2 4\n"),
                    OldDict = lookup_merkel_proofs(F#tx_pool.dict, Querys, F#tx_pool.block_trees, Height+1),
                    %io:fwrite("tx pool feeder absorb timeout 2 5\n"),
                    if
                        true -> ok;
                        (Height == 10) ->
                            io:fwrite({Querys, lists:map(fun(X) -> {X, dict:fetch(X, OldDict)} end, dict:fetch_keys(OldDict))});
                        true -> ok
                    end,
                    MinerReward = block:miner_fees(Txs2),
                    %io:fwrite("tx pool feeder absorb timeout 2 6\n"),
                    GovFees = block:gov_fees(Txs2, OldDict, Height),
                    X = txs:digest([SignedTx], OldDict, Height+1),
                    X2 = txs:digest([CBTX, SignedTx], OldDict, Height+1),
                    %io:fwrite("tx_pool_feeder digested tx.\n"),
                    
                    MinerAccount2 = accounts:dict_update(constants:master_pub(), X2, MinerReward - GovFees, none),
                    NewDict2 = accounts:dict_write(MinerAccount2, X2),
                    Dict = 
                        if
                            is_integer(F#tx_pool.block_trees) ->
                              
                    %io:fwrite("tx_pool_feeder paid miner.\n"),
                    %Facts = proofs:prove(Querys, F#tx_pool.block_trees),
                    %Facts = trees2:get_proof(Querys, F#tx_pool.block_trees, fast),
                                Facts20 = trees2:get(Querys, F#tx_pool.block_trees),
                    %io:fwrite("tx_pool_feeder got proofs.\n"),
                    %io:fwrite(Facts20),
                    %Dict = proofs:facts_to_dict(Facts20, dict:new()),
                    lists:foldl(
                             fun({{TreeID, Key}, empty}, D) ->
                                     HK = trees2:hash_key(TreeID, Key),
                                     csc:add_empty(TreeID, HK, {TreeID, Key}, D);
                                ({{TreeID, Key}, Value}, D) -> %dict:store(Key, Value, D) 
                                     HK = trees2:hash_key(TreeID, Key),
                                     csc:add(TreeID, HK, {TreeID, Key}, Value, D)
                             end, dict:new(), Facts20);
                            true ->
                                Facts = proofs:prove(Querys, F#tx_pool.block_trees),
                                proofs:facts_to_dict(Facts, dict:new())
                        end,
%                    if
%                        (Height == 10) ->
%                            io:fwrite({dict:fetch_keys(Dict)});
%                        true -> ok
%                    end,
                    %io:fwrite({Dict, Dict2}),
                    %io:fwrite({lists:map(fun(X) -> {X, dict:find(X, Dict)} end, dict:fetch_keys(Dict))}),
                    %io:fwrite("tx_pool_feeder facts in a dict.\n"),
                    SameLength = (length(dict:fetch_keys(Dict)) ==
                                      length(dict:fetch_keys(NewDict2))),
                    if
                        SameLength -> ok;
                        true -> io:fwrite({length(dict:fetch_keys(Dict)), 
                                           length(dict:fetch_keys(NewDict2)),
                                           length(dict:fetch_keys(X2)),
                                           length(dict:fetch_keys(OldDict)),
                                           dict:fetch_keys(Dict),
                                           dict:fetch_keys(NewDict2)
                                          })
                    end,
                    NC = block:no_counterfeit(Dict, NewDict2, Txs2, Height+1),
                    %io:fwrite("no counterfeit.\n"),
                    if
                        NC > 0 -> 
                            io:fwrite("counterfeit error \n"),
                            PID ! error;
                        true ->
                            %TODO, only absorb this tx if it was processed in a small enough amount of time.
                            %tx_pool:absorb_tx(X, SignedTx),
                            %io:fwrite("absorb this tx.\n"),
                            PID ! X
                    end
            end
    end.
sum_cost([], _, _) -> 0;
sum_cost([H|T], Dict, Trees) ->
    Type = element(1, H),
    Cost = case Type of
               contract_timeout_tx2 -> 0;
               _ -> governance:value(
                      trees:get(governance, Type, 
                                Dict, Trees))
           end,
    Cost + sum_cost(T, Dict, Trees).
   
%if the thing is already in the dict, then don't do anything. If it isn't in the dict, then get a copy out of the tree for it. 
lookup_merkel_proofs(Dict, [], _, _) -> Dict;
lookup_merkel_proofs(Dict, [{orders, Key}|T], Trees, Height) ->
    Dict2 = 
	case dict:find({orders, Key}, Dict) of
	    error ->
		Oracles = trees:oracles(Trees),
		{_, Oracle, _} = oracles:get(Key#key.id, Oracles),
		Orders = case Oracle of
			     empty -> orders:empty_book();
			     _ -> oracles:orders(Oracle)
			 end,
		%Orders = Oracle#oracle.orders,
		{_, Val, _} = orders:get(Key#key.pub, Orders),
		Val2 = case Val of
			   empty -> 0;
			   X -> orders:serialize(X)
			       %oracles:orders(Oracle)
		       end,
		dict:store({orders, Key}, Val2, Dict);
	    {ok, _} -> Dict
	end,
    lookup_merkel_proofs(Dict2, T, Trees, Height);
lookup_merkel_proofs(Dict, [{oracle_bets, Key}|T], Trees, Height) ->
    Dict2 = 
	case dict:find({oracle_bets, Key}, Dict) of
	    error ->
		Accounts = trees:accounts(Trees),
		{_, Account, _} = accounts:get(Key#key.pub, Accounts),
		Orders = Account#acc.bets,
		{_, Val, _} = oracle_bets:get(Key#key.id, Orders),
		Val2 = case Val of
			   empty -> 0;
			   X -> oracle_bets:serialize(X)
		       end,
		dict:store({oracle_bets, Key}, Val2, Dict);
	    {ok, _} -> Dict
	end,
    lookup_merkel_proofs(Dict2, T, Trees, Height);
lookup_merkel_proofs(Dict, [{TreeID, Key}|T], Trees, Height) ->
    case Key of
        [] -> 
            io:fwrite("tx_pool_feeder: looked up a empty key in the consensus dict.\n"),
            io:fwrite("in tree: "),
            io:fwrite(TreeID),
            io:fwrite("\n"),
            io:fwrite({TreeID, Key}),
            1=2;
        _ -> ok
    end,
    %HashedKey = trees2:hash_key(TreeID, Key),
    Dict2 = 
	%case dict:find({TreeID, Key}, Dict) of
	case csc:read({TreeID, Key}, Dict) of
	    error ->
		%Tree = trees:TreeID(Trees),
		%{_, Val, _} = TreeID:get(Key, Tree),
                %Val = trees:get(TreeID, HashedKey),
                Val = trees:get(TreeID, Key),

                PS = constants:pubkey_size() * 8,
		Val2 = case Val of
			   empty -> 0;
                           {empty, _} -> 0;
                           {<<Head2:PS>>, Many} ->
                               {<<Head2:PS>>, Many};
			   X -> X
		       end,
                HashedKey = trees2:hash_key(TreeID, Key),
                case Val2 of
                    0 -> 
                        %io:fwrite("tx_pool_feeder, looked up an empty\n"),
                        csc:add_empty(TreeID,
                           HashedKey,
                           {TreeID, Key}, Dict);
                    {<<Head:PS>>, Many2} -> 
                        io:fwrite("tx_pool_feeder, looked up an unmatched head\n"),
                        csc:add(TreeID, HashedKey, {TreeID, Key}, {unmatched_head, <<Head:PS>>, Many2, <<0:256>>}, Dict);
                    %    dict:store({unmatched, HashedKey}, Val2, Dict);
                    _ ->
                        %io:fwrite("tx_pool_feeder, looked up an unmatched link\n"),
                        csc:add(
                          TreeID, HashedKey, {TreeID, Key}, Val2,
                          Dict)
                end;
	    {empty, _, _} -> Dict;
	    {ok, _, _} -> Dict
	end,
    lookup_merkel_proofs(Dict2, T, Trees, Height).

ai2([]) -> ok;
ai2([H|T]) ->
%    case absorb_internal(H) of
%	error -> ok;
%	NewDict ->
%	    dict:find(sample, NewDict),
%	    tx_pool:absorb_tx(NewDict, H)
%    end,
    absorb_internal(H),
    ai2(T).
   
 
absorb([]) -> ok;%if one tx makes the gen_server die, it doesn't ignore the rest of the txs.
absorb([H|T]) -> absorb(H), absorb(T);
absorb(SignedTx) ->
    N = sync_mode:check(),
    case N of
	normal -> 
	    gen_server:call(?MODULE, {absorb, SignedTx});
	_ -> io:fwrite("warning, transactions don't work if you aren't in sync_mode normal"),
	    %1=2,
	    ok
    end.
absorb([], _) -> ok;
absorb([H|T], Timeout) -> 
    absorb(H, Timeout),
    absorb(T, Timeout);
absorb(Tx, Timeout) -> 
    N = sync_mode:check(),
    case N of
	normal -> 
	    gen_server:call(?MODULE, {absorb, Tx, Timeout});
	_ -> io:fwrite("warning, transactions don't work if you aren't in sync_mode normal"),
	    %1=2,
	    ok
    end.
    
absorb_async(SignedTxs) ->
    N = sync_mode:check(),
    case N of
	normal -> 
	    gen_server:cast(?MODULE, {absorb, SignedTxs});
	_ -> %io:fwrite("warning, transactions don't work well if you aren't in sync_mode normal")
	    ok
    end.
absorb_dump2(Block, STxs) ->
    N = sync_mode:check(),
    case N of
	normal -> 
	    gen_server:call(?MODULE, {absorb_dump2, Block, STxs});
	_ -> ok
    end.
    
absorb_dump(Block, STxs) ->
    N = sync_mode:check(),
    case N of
	normal -> 
	    gen_server:cast(?MODULE, {absorb_dump, Block, STxs});
	_ -> ok
    end.
dump(Block) ->
    gen_server:cast(?MODULE, {dump, Block}).
