module testnet_coins::digital_infinite_dollar {

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


    struct DigitalInfiniteDollar has key, store { }

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

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<DigitalInfiniteDollar>(
            coin_admin,
            string::utf8(b"Digital Infinite Dollar"),
            string::utf8(b"DID"),
            8, /* decimals */
            true, /* monitor_supply */
        );

        move_to(coin_admin, CapStore<BurnCapability<DigitalInfiniteDollar>> { cap: burn_cap });
        move_to(coin_admin, CapStore<FreezeCapability<DigitalInfiniteDollar>> { cap: freeze_cap });
        move_to(coin_admin, CapStore<MintCapability<DigitalInfiniteDollar>> { cap: mint_cap });
        move_to(coin_admin, Delegations<BurnCapability<DigitalInfiniteDollar>>{ inner: vector::empty<DelegatedCapability<BurnCapability<DigitalInfiniteDollar>>>() });
        move_to(coin_admin, Delegations<FreezeCapability<DigitalInfiniteDollar>>{ inner: vector::empty<DelegatedCapability<FreezeCapability<DigitalInfiniteDollar>>>() });
        move_to(coin_admin, Delegations<MintCapability<DigitalInfiniteDollar>>{ inner: vector::empty<DelegatedCapability<MintCapability<DigitalInfiniteDollar>>>() });
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

    public fun destroy_burn_cap_store(cap_store: CapStore<BurnCapability<DigitalInfiniteDollar>>) {
        let CapStore<BurnCapability<DigitalInfiniteDollar>> { cap: cap } = cap_store;
        coin::destroy_burn_cap(cap);
    }
    public fun destroy_freeze_cap_store(cap_store: CapStore<FreezeCapability<DigitalInfiniteDollar>>) {
        let CapStore<FreezeCapability<DigitalInfiniteDollar>> { cap: cap } = cap_store;
        coin::destroy_freeze_cap(cap);
    }
    public fun destroy_mint_cap_store(cap_store: CapStore<MintCapability<DigitalInfiniteDollar>>) {
        let CapStore<MintCapability<DigitalInfiniteDollar>> { cap: cap } = cap_store;
        coin::destroy_mint_cap(cap);
    }

    public entry fun revoke_burn_capability(sender: &signer, account: address) acquires AdminStore, CapStore {
        only_admin_or_self(sender, account);
        assert!(exists<CapStore<BurnCapability<DigitalInfiniteDollar>>>(account), error::not_found(ENO_CAPABILITIES));
        destroy_burn_cap_store(move_from<CapStore<BurnCapability<DigitalInfiniteDollar>>>(account));
    }
    public entry fun revoke_freeze_capability(sender: &signer, account: address) acquires AdminStore, CapStore {
        only_admin_or_self(sender, account);
        assert!(exists<CapStore<FreezeCapability<DigitalInfiniteDollar>>>(account), error::not_found(ENO_CAPABILITIES));
        destroy_freeze_cap_store(move_from<CapStore<FreezeCapability<DigitalInfiniteDollar>>>(account));
    }
    public entry fun revoke_mint_capability(sender: &signer, account: address) acquires AdminStore, CapStore {
        only_admin_or_self(sender, account);
        assert!(exists<CapStore<MintCapability<DigitalInfiniteDollar>>>(account), error::not_found(ENO_CAPABILITIES));
        destroy_mint_cap_store(move_from<CapStore<MintCapability<DigitalInfiniteDollar>>>(account));
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
        coin: Coin<DigitalInfiniteDollar>,
        cap_store: &CapStore<BurnCapability<DigitalInfiniteDollar>>
    )   {
        let burn_cap = &cap_store.cap;
        coin::burn<DigitalInfiniteDollar>(coin, burn_cap);
    }

    public fun freeze_account(
        account_to_freeze: address,
        cap_store: &CapStore<FreezeCapability<DigitalInfiniteDollar>>
    )   {
        let freeze_cap = &cap_store.cap;
        coin::freeze_coin_store<DigitalInfiniteDollar>(account_to_freeze, freeze_cap);
    }

    public fun mint(
        amount: u64,
        cap_store: &CapStore<MintCapability<DigitalInfiniteDollar>>
    ): Coin<DigitalInfiniteDollar>   {
        let mint_cap = &cap_store.cap;
        coin::mint<DigitalInfiniteDollar>(amount, mint_cap)
    }


    // entry function
    public entry fun burn_entry(
        account: &signer,
        amount: u64
    ) acquires CapStore {
        let account_addr = signer::address_of(account);
        assert!(exists<CapStore<BurnCapability<DigitalInfiniteDollar>>>(account_addr), error::not_found(ENO_CAPABILITIES));
        let burn_cap = &borrow_global<CapStore<BurnCapability<DigitalInfiniteDollar>>>(account_addr).cap;
        coin::burn_from<DigitalInfiniteDollar>(account_addr, amount, burn_cap);
    }

    public entry fun freeze_entry(
        account: &signer,
        account_to_freeze: address,
    ) acquires CapStore {
        let account_addr = signer::address_of(account);
        assert!(exists<CapStore<FreezeCapability<DigitalInfiniteDollar>>>(account_addr), error::not_found(ENO_CAPABILITIES));
        let freeze_cap = &borrow_global<CapStore<FreezeCapability<DigitalInfiniteDollar>>>(account_addr).cap;
        coin::freeze_coin_store<DigitalInfiniteDollar>(account_to_freeze, freeze_cap);
    }

    public entry fun mint_entry(
        account: &signer,
        dst_addr: address,
        amount: u64
    ) acquires CapStore {
        let account_addr = signer::address_of(account);
        assert!(exists<CapStore<MintCapability<DigitalInfiniteDollar>>>(account_addr), error::not_found(ENO_CAPABILITIES));
        let mint_cap = &borrow_global<CapStore<MintCapability<DigitalInfiniteDollar>>>(account_addr).cap;
        let coins_minted = coin::mint<DigitalInfiniteDollar>(amount, mint_cap);
        coin::deposit<DigitalInfiniteDollar>(dst_addr, coins_minted);
    }
}