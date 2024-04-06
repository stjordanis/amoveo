Amoveo
==========

Amoveo is a blockchain meant for enforcement of investment and insurance contracts.

Amoveo contracts are enforced using state-channels. This means fees are low, contracts are nearly instant and can support a global audience.

Amoveo has futarchy-based oracle technology.
Amoveo can learn facts about our world and enforce the outcome of contracts that are governed by these facts.
This, for example, enables you to bet on the price of Amazon shares.

The variables that define how to participate in Amoveo can be modified by the Amoveo community using futarchy, a betting-type governance mechanism.
This way Amoveo will always stay optimally tuned to produce the best results.


[Amoveo whitepaper](https://github.com/zack-bitcoin/amoveo-docs/blob/master/white_paper.md).


Amoveo main net was launched at 11:00 AM GMT on March 2, 2018.

[The current market cap in VEO](http://159.89.87.58:8080/ext/getmoneysupply)

## Community
[Amoveo forum on reddit](https://www.reddit.com/r/Amoveo/)

[Amoveo announcements on twitter](https://twitter.com/zack_bitcoin)

[Amoveo on Telegram](https://t.me/amoveo)

[Amoveo on Discord. Русский чат. 中文聊天.](https://discord.gg/a52szJw)

[Historic difficulty in depth.](https://amoveo.tools/)

[Amoveo website from the Exantech, the same people who wrote an iphone and android app](https://amoveo.io/)

[Website for exploring oracles and governance variables](https://veo.sh/oracles)
<!---

[Statistics page to see historic difficulty, blocktime, hashrate, and more.](https://jimhsu.github.io/amoveo-stats/)
--->

<!---
## Smart contracts

[here is documentation](https://github.com/zack-bitcoin/amoveo-docs/blob/master/light_node/p2p_derivatives.md) for how to make bets on any topic using Amoveo.
---->


## Light node

The most secure way to use the light node is to download it from github. https://github.com/zack-bitcoin/light-node-amoveo
This is a cryptoeconomically secure way to use Amoveo.

you can use the light node less securely by clicking [this link](http://64.227.21.70:8080/home.html). This is the easiest way to get started.
Using this light node is the same as trusting this server with your money.

An alternative exan.tech made a light node with a different user interface that they host here: Amoveo.exan.tech
Using this light node is the same as trusting them with your money.

This light node downloads headers and verifies the proof of work.
It verifies the merkle proofs for all blockchain state you download to ensure security equivalent to a full node, provided you wait for enough confirmations.


## Block Explorer

[Veopool explorer](http://explorer.veopool.pw/)

<!---
[Veoscan explorer. Nodes, blocks, txs, markets, holders, and more.](http://veoscan.io/)

[mveo explorer. historic difficulty analisys](https://mveo.net/)

[Amoveo.tools historical difficulty chart](https://amoveo.tools/)
--->

The block explorer for the network is [here](http://64.227.21.70:8080/explorer.html).
This explorer can host markets.




## Full node
[Launch an erlang full node and connect to the network](https://github.com/zack-bitcoin/amoveo-docs/blob/master/getting-started/turn_it_on.md)

[Issue commands to your full node](https://github.com/zack-bitcoin/amoveo-docs/blob/master/api/commands.md)
Commands such as:
* turning the node off without corrupting the database.
* looking up information from the blockchain or it's history.
* making a server that collects fees by routing payments or making markets
* participating in the oracle mechanism or governance mechanism.

## Mining

[This is an open-source miner for AMD and Nvidia GPU. Currently only works with Linux](https://github.com/zack-bitcoin/VeoCL)

[This is a miner. it is for Nvidia or AMD GPUs. It is closed-source.](https://github.com/PhamHuong92/VeoMiner)

[here is another closed source miner](https://github.com/krypdkat/AmoveoMinerMan)

<!-----

[Comino appears to be selling some fpga software to mine veo](https://comino.com/shop)

---->

[here is miners for 5 different kinds of fpga](https://github.com/dedmarozz)

Amoveo's mining algorithm uses SHA256 like bitcoin. But it is a little different, so bitcoin ASICs cannot be used to mine Amoveo.

Full node keys are stored in `_build/prod/rel/amoveo_core/keys/keys.db`


## Mining Pools

[the only public mining pool](http://159.223.85.216:8085/main.html)


[Run your own pool.](https://github.com/zack-bitcoin/amoveo-docs/blob/master/getting_started/mining.md)

[Run your own pool.](https://github.com/zack-bitcoin/amoveo-docs/blob/master/getting_started/mining.md)

## Trading


There are people trading now on discord https://discord.gg/xJQcVaT

<!---

Be very careful using exchanges. They are centralized, the operator can take all the veo if they wanted.

Qtrade exchange for BTC-VEO trading: https://qtrade.io/market/VEO_BTC

[graviex exchange](https://github.com/zack-bitcoin/amoveo/blob/master/docs/exchanges/graviex_links.md)

A1 exchange for ETH-VEO and BTC-VEO trading (previously called amoveo.exchange): https://a1.exchange/

## browser extentions
Firefox. It can be found here. https://addons.mozilla.org/en-US/firefox/addon/amoveo-wallet/ and the source code is here https://github.com/johnnycash77/amoveo3-wallet

--->

## Software to launch a new mining pool


[A mining pool](https://github.com/zack-bitcoin/amoveo-mining-pool)


# Developers

If you want to build on top of Amoveo [read the developer's guide](https://github.com/zack-bitcoin/amoveo-docs/blob/master/getting-started/quick_start_developer_guide.md)


