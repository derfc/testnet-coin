module testnet_coins::a_fenture_finance_dao {

    use std::string;
    use std::error;
    use std::option::{Self, Option};
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Coin, BurnCapability, FreezeCapability, MintCapability, Self};

    const ENO_CAPABILITIES: u64 = 1;
    const EALREADY_HAVE_CAP: u64 = 2;
    const EALREADY_DELEGATED: u64 = 3;
    const EDELEGATION_NOT_FOUND: u64 = 4;
    const ENOT_ADMIN: u64 = 5;
    const ENOT_ADMIN_NOR_SELF: u64 = 6;


    struct AFentureFinanceDao has key, store { }

    struct CapStore<CapType: store + copy> has key, store {
        cap: CapType,
    }

    struct DelegatedCapability<phantom CapType> has store {
        to: address,
    }
    struct Delegations<phantom CapType> has key {
        inner: vector<DelegatedCapability<CapType>>,
    }

    struct AdminStore has key {
        admin: address
    }
    
    public entry fun initialize(coin_admin: &signer) {
        assert!(signer::address_of(coin_admin) == @testnet_coins, error::permission_denied(ENOT_ADMIN));

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<AFentureFinanceDao>(
            coin_admin,
            string::utf8(b"A Fenture Finance Dao"),
            string::utf8(b"aFFD"),
            8, /* decimals */
            true, /* monitor_supply */
        );

        move_to(coin_admin, CapStore<BurnCapability<AFentureFinanceDao>> { cap: burn_cap });
        move_to(coin_admin, CapStore<FreezeCapability<AFentureFinanceDao>> { cap: freeze_cap });
        move_to(coin_admin, CapStore<MintCapability<AFentureFinanceDao>> { cap: mint_cap });
        move_to(coin_admin, Delegations<BurnCapability<AFentureFinanceDao>>{ inner: vector::empty<DelegatedCapability<BurnCapability<AFentureFinanceDao>>>() });
        move_to(coin_admin, Delegations<FreezeCapability<AFentureFinanceDao>>{ inner: vector::empty<DelegatedCapability<FreezeCapability<AFentureFinanceDao>>>() });
        move_to(coin_admin, Delegations<MintCapability<AFentureFinanceDao>>{ inner: vector::empty<DelegatedCapability<MintCapability<AFentureFinanceDao>>>() });
        move_to(coin_admin, AdminStore{ admin: @testnet_coins });

    }

    // delegate capabilities
    public entry fun change_admin(admin: &signer, new_admin: address) acquires AdminStore {
        only_admin(admin);
        borrow_global_mut<AdminStore>(@testnet_coins).admin = new_admin;
    }

    public entry fun delegate_capability<CapType>(admin: &signer, to: address) acquires AdminStore, Delegations {
        only_admin(admin);
        let delegations = &mut borrow_global_mut<Delegations<CapType>>(@testnet_coins).inner;
        let i = 0;
        while (i < vector::length(delegations)) {
            let element = vector::borrow(delegations, i);
            assert!(element.to != to, error::invalid_argument(EALREADY_DELEGATED));
            i = i + 1;
        };
        vector::push_back(delegations, DelegatedCapability<CapType> { to: to });
    }

    public entry fun claim_capability<CapType: copy + store>(account: &signer) acquires Delegations, CapStore {
        let delegations = &mut borrow_global_mut<Delegations<CapType>>(@testnet_coins).inner;
        let maybe_index = find_delegation<CapType>(signer::address_of(account), freeze(delegations));
        assert!(option::is_some(&maybe_index), error::invalid_argument(EDELEGATION_NOT_FOUND));
        let idx = *option::borrow(&maybe_index);
        let DelegatedCapability<CapType> { to : _ } = vector::swap_remove(delegations, idx);
        let cap = borrow_global<CapStore<CapType>>(@testnet_coins).cap;
        move_to(account, CapStore<CapType> { cap });
    }

    public fun store_capability<CapType: copy + store>(account: &signer, cap_store: CapStore<CapType>)   {
        let account_addr = signer::address_of(account);
        assert!(!exists<CapStore<CapType>>(account_addr), error::invalid_argument(EALREADY_HAVE_CAP),);
        move_to(account, cap_store);
    }

    public fun extract_capability<CapType: copy + store>(account: &signer): CapStore<CapType> acquires CapStore {
        let account_addr = signer::address_of(account);
        assert!(exists<CapStore<CapType>>(account_addr), error::not_found(ENO_CAPABILITIES));
        move_from<CapStore<CapType>>(account_addr)
    }

    public fun destroy_burn_cap_store(cap_store: CapStore<BurnCapability<AFentureFinanceDao>>) {
        let CapStore<BurnCapability<AFentureFinanceDao>> { cap: cap } = cap_store;
        coin::destroy_burn_cap(cap);
    }
    public fun destroy_freeze_cap_store(cap_store: CapStore<FreezeCapability<AFentureFinanceDao>>) {
        let CapStore<FreezeCapability<AFentureFinanceDao>> { cap: cap } = cap_store;
        coin::destroy_freeze_cap(cap);
    }
    public fun destroy_mint_cap_store(cap_store: CapStore<MintCapability<AFentureFinanceDao>>) {
        let CapStore<MintCapability<AFentureFinanceDao>> { cap: cap } = cap_store;
        coin::destroy_mint_cap(cap);
    }

    public entry fun revoke_burn_capability(sender: &signer, account: address) acquires AdminStore, CapStore {
        only_admin_or_self(sender, account);
        assert!(exists<CapStore<BurnCapability<AFentureFinanceDao>>>(account), error::not_found(ENO_CAPABILITIES));
        destroy_burn_cap_store(move_from<CapStore<BurnCapability<AFentureFinanceDao>>>(account));
    }
    public entry fun revoke_freeze_capability(sender: &signer, account: address) acquires AdminStore, CapStore {
        only_admin_or_self(sender, account);
        assert!(exists<CapStore<FreezeCapability<AFentureFinanceDao>>>(account), error::not_found(ENO_CAPABILITIES));
        destroy_freeze_cap_store(move_from<CapStore<FreezeCapability<AFentureFinanceDao>>>(account));
    }
    public entry fun revoke_mint_capability(sender: &signer, account: address) acquires AdminStore, CapStore {
        only_admin_or_self(sender, account);
        assert!(exists<CapStore<MintCapability<AFentureFinanceDao>>>(account), error::not_found(ENO_CAPABILITIES));
        destroy_mint_cap_store(move_from<CapStore<MintCapability<AFentureFinanceDao>>>(account));
    }

    fun find_delegation<CapType>(addr: address, delegations: &vector<DelegatedCapability<CapType>>): Option<u64> {
        let i = 0;
        let len = vector::length(delegations);
        let index = option::none();
        while (i < len) {
            let element = vector::borrow(delegations, i);
            if (element.to == addr) {
                index = option::some(i);
                break
            };
            i = i + 1;
        };
        index
    }

    fun only_admin(admin: &signer) acquires AdminStore {
        assert!(is_admin(admin), error::permission_denied(ENOT_ADMIN));
    }

    fun only_admin_or_self(sender: &signer, account: address) acquires AdminStore {
        assert!(is_admin(sender) || signer::address_of(sender) == account, error::permission_denied(ENOT_ADMIN_NOR_SELF));
    }

    fun is_admin(admin: &signer): bool acquires AdminStore {
        signer::address_of(admin) == borrow_global<AdminStore>(@testnet_coins).admin
    }


    // privileged function
    public fun burn(
        coin: Coin<AFentureFinanceDao>,
        cap_store: &CapStore<BurnCapability<AFentureFinanceDao>>
    )   {
        let burn_cap = &cap_store.cap;
        coin::burn<AFentureFinanceDao>(coin, burn_cap);
    }

    public fun freeze_account(
        account_to_freeze: address,
        cap_store: &CapStore<FreezeCapability<AFentureFinanceDao>>
    )   {
        let freeze_cap = &cap_store.cap;
        coin::freeze_coin_store<AFentureFinanceDao>(account_to_freeze, freeze_cap);
    }

    public fun mint(
        amount: u64,
        cap_store: &CapStore<MintCapability<AFentureFinanceDao>>
    ): Coin<AFentureFinanceDao>   {
        let mint_cap = &cap_store.cap;
        coin::mint<AFentureFinanceDao>(amount, mint_cap)
    }


    // entry function
    public entry fun burn_entry(
        account: &signer,
        amount: u64
    ) acquires CapStore {
        let account_addr = signer::address_of(account);
        assert!(exists<CapStore<BurnCapability<AFentureFinanceDao>>>(account_addr), error::not_found(ENO_CAPABILITIES));
        let burn_cap = &borrow_global<CapStore<BurnCapability<AFentureFinanceDao>>>(account_addr).cap;
        coin::burn_from<AFentureFinanceDao>(account_addr, amount, burn_cap);
    }

    public entry fun freeze_entry(
        account: &signer,
        account_to_freeze: address,
    ) acquires CapStore {
        let account_addr = signer::address_of(account);
        assert!(exists<CapStore<FreezeCapability<AFentureFinanceDao>>>(account_addr), error::not_found(ENO_CAPABILITIES));
        let freeze_cap = &borrow_global<CapStore<FreezeCapability<AFentureFinanceDao>>>(account_addr).cap;
        coin::freeze_coin_store<AFentureFinanceDao>(account_to_freeze, freeze_cap);
    }

    public entry fun mint_entry(
        account: &signer,
        dst_addr: address,
        amount: u64
    ) acquires CapStore {
        let account_addr = signer::address_of(account);
        assert!(exists<CapStore<MintCapability<AFentureFinanceDao>>>(account_addr), error::not_found(ENO_CAPABILITIES));
        let mint_cap = &borrow_global<CapStore<MintCapability<AFentureFinanceDao>>>(account_addr).cap;
        let coins_minted = coin::mint<AFentureFinanceDao>(amount, mint_cap);
        coin::deposit<AFentureFinanceDao>(dst_addr, coins_minted);
    }
}