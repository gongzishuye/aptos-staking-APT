/// user can stack APT and get FREE for rewards
/// rewards: FREE reward = APT amount * 2
module APTStacking::stacking {

    use std::signer;
    use std::string;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self};
    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};
    use aptos_framework::timestamp;

    const MIN_STACKING_AMOUNT: u64 = 10000;

    const ERR_NOT_ADMIN: u64 = 0x001;
    const ERR_TOO_LESS_STACKING_AMOUNT: u64 = 0x002;
    const ERR_NOT_ENOUGH_APT: u64 = 0x003;
    const ERR_EXCEED_MAX_STAKE_AMOUNT: u64 = 0x004;
    const ERR_USER_NOT_STAKE: u64 = 0x005;
    const ERR_NOT_EXPIRE: u64 = 0x006;
    const ERR_WRONG_STAKE_AMOUNT: u64 = 0x007;

    struct FREE has key {
    }

    struct StackInfo has key {
        stack_amount: u64,
        stack_time: u64
    }

    struct AgentInfo has key {
        signer_cap: account::SignerCapability,
        stack_amount: u64,
        max_stack_amount: u64
    }

    struct FreeAbilities has key {
        burn: BurnCapability<FREE>,
        freeze: FreezeCapability<FREE>,
        mint: MintCapability<FREE>
    }

    fun init(admin: &signer, max_stack_amount: u64) {
        assert!(max_stack_amount >= MIN_STACKING_AMOUNT, ERR_TOO_LESS_STACKING_AMOUNT);
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @APTStacking, ERR_NOT_ADMIN);

        let (signer, signer_cap) = account::create_resource_account(admin, b"FREE");
        coin::register<AptosCoin>(&signer);
        move_to<AgentInfo>(admin, AgentInfo {
            signer_cap,
            stack_amount: 0,
            max_stack_amount
        });

        let (burn, freeze, mint) = coin::initialize<FREE>(
            admin,
            string::utf8(b"FREE Coin"),
            string::utf8(b"FREE"),
            8,
            true,
        );

        coin::register<FREE>(&signer);
        let total_coins = coin::mint(max_stack_amount * 2, &mint);
        coin::deposit(signer::address_of(&signer), total_coins);

        move_to<FreeAbilities>(&signer, FreeAbilities {
            burn, freeze, mint
        });
    }

    /// 1. stacker transfer stack_amount APT to @Agent
    /// 2. @Agent add the stack_amount
    fun stack(stacker: &signer, stack_amount: u64) acquires AgentInfo {
        let stacker_addr = signer::address_of(stacker);
        if(!coin::is_account_registered<AptosCoin>(stacker_addr)) {
            coin::register<AptosCoin>(stacker);
        };

        let agent_info = borrow_global_mut<AgentInfo>(@Agent);
        let apt_balance = coin::balance<AptosCoin>(stacker_addr);
        assert!(apt_balance > stack_amount, ERR_NOT_ENOUGH_APT);
        let stack_coins = coin::withdraw<AptosCoin>(stacker, stack_amount);
        coin::deposit(@Agent, stack_coins);
        assert!(agent_info.max_stack_amount >= agent_info.stack_amount + stack_amount, ERR_EXCEED_MAX_STAKE_AMOUNT);
        agent_info.stack_amount = agent_info.stack_amount + stack_amount;

        move_to<StackInfo>(stacker, StackInfo {
            stack_amount,
            stack_time: timestamp::now_seconds()
        });

    }

    /// 1. verify whether stack expired
    /// 2. @Agent transfer stacked APT to stacker
    /// 3. @Agent transfer double amount APT to stacker
    fun unstack(stacker: &signer) acquires StackInfo, AgentInfo {
        let stacker_addr = signer::address_of(stacker);
        assert!(exists<StackInfo>(stacker_addr), ERR_USER_NOT_STAKE);
        assert!(stack_expire(stacker), ERR_NOT_EXPIRE);

        let stack_info = borrow_global<StackInfo>(stacker_addr);

        let agent_info = borrow_global_mut<AgentInfo>(@Agent);
        assert!(agent_info.stack_amount > stack_info.stack_amount, ERR_WRONG_STAKE_AMOUNT);

        let agent_signer = account::create_signer_with_capability(&agent_info.signer_cap);
        coin::transfer<AptosCoin>(&agent_signer, stacker_addr, stack_info.stack_amount);
        if(!coin::is_account_registered<FREE>(stacker_addr)) {
            coin::register<FREE>(stacker);
        };
        coin::transfer<FREE>(&agent_signer, stacker_addr, stack_info.stack_amount * 2);
        agent_info.stack_amount = agent_info.stack_amount - stack_info.stack_amount;
    }

    fun stack_expire(stacker: &signer): bool acquires StackInfo {
        let stacker_addr = signer::address_of(stacker);
        let stack_info = borrow_global<StackInfo>(stacker_addr);
        let duration = timestamp::now_seconds() - stack_info.stack_time;
        if(duration > 3600 * 24 * 10) {
            true
        } else {
            false
        }
    }
}