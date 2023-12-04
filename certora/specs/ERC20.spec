import "helpers.spec";
import "IERC20.spec";
import "IERC2612.spec";

methods {
    // exposed for FV
    function mint(address,uint256) external;
    function burn(address,uint256) external;
}

function xWELLAddress() returns address {
    return currentContract;
}

function timestampMax() returns uint256 {
    return 2 ^ 32 - 1;
}

function uintMax() returns uint256 {
    return 2 ^ 256 - 1;
}

function balanceMax() returns uint256 {
    return 2 ^ 224 - 1;
}

/// Preconditions:
///    - `balanceOf` is a uint256, that is less than or equal to uint224 max
///    - block timestamp is under or equal uint32 max

/// Invariants:
///    - `sumBalances` == `totalSupply`
///    - `votingPower` <= `uint224 max`
///    - `sumVotingPower` <= `totalSupply`
///    - `totalSupply` <= `maxSupply`
///    - `delegated voting power` <= `votingPower`
///    - user A delegating to user B => user B voting power >= user A voting power
///    - `votingPower` <= balanceOf single delegator ==> unfortunately cannot reason about this
///    - number of checkpoints == total number of times transfer has been called by a user, and
///    how many times a user has received tokens + the amount of times that mint/burn has been
///    called to or for them.

/// Buffer limits
///    - `bufferCap` >= `minBufferCap`
///    - `rateLimitPerSecond` <= `maxRateLimitPerSecond`

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Ghost & hooks: sum of all balances                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
ghost mathint sumBalances {
    init_state axiom sumBalances == 0;
    axiom forall address a. forall address b. (
        (a == b => sumBalances >= to_mathint(balanceOfMirror[a])) &&
        (a != b => sumBalances >= balanceOfMirror[a] + balanceOfMirror[b])
    );
    axiom forall address a. forall address b. forall address c. (
        a != b && a != c && b != c => 
        sumBalances >= balanceOfMirror[a] + balanceOfMirror[b] + balanceOfMirror[c]
    );
}


/// @title A ghost to mirror the balances, needed for `sumBalances`
ghost mapping(address => uint256) balanceOfMirror {
    init_state axiom forall address a. balanceOfMirror[a] == 0;
}

/// @title A ghost to mirror the totalSupply in ERC20Upgradeable, needed for checking the total supply
ghost mapping(uint256 => uint256) totalSupplyVotesMirror {
    init_state axiom forall uint256 a. totalSupplyVotesMirror[a] == 0;
}

ghost uint256 totalSupplyVotesLastUpdateTime {
    init_state axiom totalSupplyVotesLastUpdateTime == 0;
}

ghost mathint totalSupplyVotesWriteCount {
    init_state axiom totalSupplyVotesWriteCount == 0;
}

ghost mathint totalSupplyStandardWriteCount {
    init_state axiom totalSupplyStandardWriteCount == 0;
}

/// @notice a ghost to mirror the totalSupply in the ERC20 token contract,
/// needed for checking the total supply
ghost mathint totalSupplyStandardMirror {
    init_state axiom totalSupplyStandardMirror == 0;
    axiom sumBalances <= totalSupplyStandardMirror;

    axiom forall address a. forall address b. forall address c. (
        a != b && a != c && b != c => 
        totalSupplyStandardMirror >= balanceOfMirror[a] + balanceOfMirror[b] + balanceOfMirror[c]
    );
}

/// @title The hook for writing to total supply checkpoints
hook Sstore _totalSupply uint256 newTotalSupply (uint256 oldTotalSupply) STORAGE
{
    totalSupplyStandardWriteCount = totalSupplyStandardWriteCount + 1;
    totalSupplyStandardMirror = newTotalSupply;
}

/// @title The hook for writing to total supply checkpoints for votes
/// only grab the last 224 bits of the total supply
hook Sstore _totalSupplyCheckpoints[INDEX uint256 timestamp].(offset 4) uint224 newTotalSupply (uint224 oldTotalSupply) STORAGE
{
    totalSupplyVotesWriteCount = totalSupplyVotesWriteCount + 1;
    totalSupplyVotesLastUpdateTime = timestamp;
    totalSupplyVotesMirror[timestamp] = newTotalSupply;
}

// Because `balance` has a uint256 type, any balance addition in CVL1 behaved as a `require_uint256()` casting,
// leaving out the possibility of overflow. This is not the case in CVL2 where casting became more explicit.
// A counterexample in CVL2 is having an initial state where Alice initial balance is larger than totalSupply, which 
// overflows Alice's balance when receiving a transfer. This is not possible unless the contract is deployed into an 
// already used address (or upgraded from corrupted state).
// We restrict such behavior by making sure no balance is greater than the sum of balances.
hook Sload uint256 balance _balances[KEY address addr] STORAGE {
    require sumBalances >= to_mathint(balance);
}

/// @title The hook
hook Sstore _balances[KEY address user] uint256 new_balance (uint256 old_balance) STORAGE
{
    sumBalances = sumBalances + new_balance - old_balance;
    balanceOfMirror[user] = new_balance;
}

/// @title Formally prove that `balanceOfMirror` mirrors `balanceOf`
invariant mirrorIsTrue(address a)
    balanceOfMirror[a] == balanceOf(a);

invariant totalSupplyVotesMirrorMatchesCurrentTotalSupplyMirror()
    totalSupplyVotesLastUpdateTime > 0 => to_mathint(totalSupplyVotesMirror[totalSupplyVotesLastUpdateTime]) == totalSupplyStandardMirror;

invariant totalSupplyUpdatesInSync()
    totalSupplyVotesWriteCount == totalSupplyStandardWriteCount;

invariant balanceOfLteUint224Max(address a)
    balanceOf(a) <= balanceMax() {
        preserved {
            requireInvariant totalSupplyLteMax();
            requireInvariant mirrorIsTrue(a);
            requireInvariant totalSupplyIsSumOfBalances();
        }
    }

/// vote count cannot exceed uint224 max

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: totalSupply is the sum of all balances                                                                   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant totalSupplyIsSumOfBalances()
    to_mathint(totalSupply()) == sumBalances;

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: totalSupply is less than or equal to the max total supply                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant totalSupplyLteMax()
    totalSupply() <= MAX_SUPPLY() {
        preserved {
            requireInvariant totalSupplyIsSumOfBalances();
        }
    }

invariant delegateIsGreaterOrEqualBalanceIndividual(address a)
    a != 0 && delegates(a) != 0 => getVotes(delegates(a)) >= balanceOf(a) {
        preserved {
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(a);
            requireInvariant mirrorIsTrue(a);
            requireInvariant addressZeroCannotDelegate();
            requireInvariant corretCheckpoints(a);
        }
    }

/// - user A delegating to user B => user B voting power >= balanceOf user A
/// do not consider case where b is address 0
/// do not consider case where number of checkpoints is uintMax() as it will overflow, and calls to getVotes will fail
/// because it will look up at index 0, when it should look up uint256 max
invariant delegateIsGreaterOrEqual(address a, address b)
    ((b != 0 && a != 0) &&
    (delegates(a) == b) => getVotes(b) >= balanceOf(a) &&
    (delegates(b) == a) => getVotes(a) >= balanceOf(b)) {
        preserved {
            requireInvariant doubleDelegateIsGreaterOrEqual(a, b);
            requireInvariant doubleDelegateIsGreaterOrEqual(b, a);
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(a);
            requireInvariant userVotesLteTotalSupply(b); /// might not need this
            requireInvariant mirrorIsTrue(a);
            requireInvariant mirrorIsTrue(b);
            requireInvariant addressZeroCannotDelegate();

            requireInvariant corretCheckpoints(a);
            requireInvariant corretCheckpoints(b);

            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(a);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(b);
        }
        preserved mint(address to, uint256 amount) with (env e) {
            requireInvariant doubleDelegateIsGreaterOrEqual(a, b);
            requireInvariant doubleDelegateIsGreaterOrEqual(b, a);

            requireInvariant doubleDelegateIsGreaterOrEqual(to, e.msg.sender);
            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, to);

            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, delegates(e.msg.sender));
            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, delegates(to));

            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(a);
            requireInvariant userVotesLteTotalSupply(b); /// might not need this
            requireInvariant userVotesLteTotalSupply(to);
            requireInvariant userVotesLteTotalSupply(e.msg.sender);

            requireInvariant mirrorIsTrue(a);
            requireInvariant mirrorIsTrue(b);
            requireInvariant mirrorIsTrue(to);
            requireInvariant mirrorIsTrue(e.msg.sender); /// might not need this

            requireInvariant addressZeroCannotDelegate();

            requireInvariant corretCheckpoints(a);
            requireInvariant corretCheckpoints(b);
            requireInvariant corretCheckpoints(e.msg.sender);
        }
        preserved burn(address to, uint256 amount) with (env e) {
            requireInvariant doubleDelegateIsGreaterOrEqual(a, b);
            requireInvariant doubleDelegateIsGreaterOrEqual(b, a);

            // requireInvariant doubleDelegateIsGreaterOrEqual(to, e.msg.sender);
            // requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, to);

            // requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, delegates(e.msg.sender));
            // requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, delegates(to));
            // requireInvariant doubleDelegateIsGreaterOrEqual(delegates(to), e.msg.sender);
            requireInvariant doubleDelegateIsGreaterOrEqual(to, delegates(to));
            requireInvariant doubleDelegateIsGreaterOrEqual(delegates(to), to);

            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(a);
            requireInvariant userVotesLteTotalSupply(b); /// might not need this
            requireInvariant userVotesLteTotalSupply(to);
            requireInvariant userVotesLteTotalSupply(e.msg.sender);

            requireInvariant mirrorIsTrue(a);
            requireInvariant mirrorIsTrue(b);
            requireInvariant mirrorIsTrue(to);
            requireInvariant mirrorIsTrue(e.msg.sender); /// might not need this

            requireInvariant addressZeroCannotDelegate();

            requireInvariant corretCheckpoints(a);
            requireInvariant corretCheckpoints(b);
            requireInvariant corretCheckpoints(e.msg.sender);
        }
        preserved transfer(address to, uint256 amount) with (env e) {
            requireInvariant doubleDelegateIsGreaterOrEqual(a, b);
            requireInvariant doubleDelegateIsGreaterOrEqual(b, a);

            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, b);
            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, a);

            requireInvariant doubleDelegateIsGreaterOrEqual(to, e.msg.sender);
            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, to);

            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, delegates(e.msg.sender));
            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, delegates(to));

            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(a);
            requireInvariant userVotesLteTotalSupply(b); /// might not need this
            requireInvariant userVotesLteTotalSupply(to);
            requireInvariant userVotesLteTotalSupply(e.msg.sender);

            requireInvariant mirrorIsTrue(a);
            requireInvariant mirrorIsTrue(b);
            requireInvariant mirrorIsTrue(to);
            requireInvariant mirrorIsTrue(e.msg.sender); /// might not need this

            requireInvariant addressZeroCannotDelegate();

            requireInvariant corretCheckpoints(to);
            requireInvariant corretCheckpoints(e.msg.sender);

            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(a);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(b);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(to);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(e.msg.sender);
        }
        preserved transferFrom(address from, address to, uint256 amount) with (env e) {
            requireInvariant doubleDelegateIsGreaterOrEqual(from, to);
            requireInvariant doubleDelegateIsGreaterOrEqual(to, from);

            requireInvariant doubleDelegateIsGreaterOrEqual(delegates(from), delegates(to));
            requireInvariant doubleDelegateIsGreaterOrEqual(delegates(to), delegates(from));

            requireInvariant doubleDelegateIsGreaterOrEqual(delegates(from), delegates(to));
            requireInvariant doubleDelegateIsGreaterOrEqual(delegates(from), delegates(to));

            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(to);
            requireInvariant userVotesLteTotalSupply(from);

            requireInvariant mirrorIsTrue(to);
            requireInvariant mirrorIsTrue(from);

            requireInvariant addressZeroCannotDelegate();

            requireInvariant corretCheckpoints(to);
            requireInvariant corretCheckpoints(from);

            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(a);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(b);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(to);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(from);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(e.msg.sender);
        }
        preserved delegate(address to) with (env e) {
            requireInvariant doubleDelegateIsGreaterOrEqual(a, b);
            requireInvariant doubleDelegateIsGreaterOrEqual(b, a);

            requireInvariant doubleDelegateIsGreaterOrEqual(to, e.msg.sender);
            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, to);

            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, delegates(e.msg.sender));
            requireInvariant doubleDelegateIsGreaterOrEqual(e.msg.sender, delegates(to));

            requireInvariant delegateIsGreaterOrEqual(a, b);
            requireInvariant delegateIsGreaterOrEqual(e.msg.sender, to);
            requireInvariant delegateIsGreaterOrEqual(e.msg.sender, a);
            requireInvariant delegateIsGreaterOrEqual(e.msg.sender, b);

            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(a);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(b);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(to);
            requireInvariant delegateIsGreaterOrEqualBalanceIndividual(e.msg.sender);

            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(a);
            requireInvariant userVotesLteTotalSupply(b); /// might not need this
            requireInvariant userVotesLteTotalSupply(to);
            requireInvariant userVotesLteTotalSupply(e.msg.sender);

            requireInvariant mirrorIsTrue(a);
            requireInvariant mirrorIsTrue(b);
            requireInvariant mirrorIsTrue(to);
            requireInvariant mirrorIsTrue(e.msg.sender); /// might not need this

            requireInvariant addressZeroCannotDelegate();
            requireInvariant zeroAddressNoBalance();

            requireInvariant corretCheckpoints(to);
            requireInvariant corretCheckpoints(e.msg.sender);
        }
    }

invariant corretCheckpoints(address a) 
    to_mathint(numCheckpoints(a)) <= to_mathint(timestampMax()) {
        preserved {
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(a);
            requireInvariant mirrorIsTrue(a);
            requireInvariant addressZeroCannotDelegate();
            require(to_mathint(numCheckpoints(a)) <= to_mathint(timestampMax() - 1));
        }
    }

/// do not consider case where number of checkpoints is uintMax() as it will overflow, and calls to getVotes will fail
/// because it will look up at index 0, when it should look up uint256 max
invariant doubleDelegateIsGreaterOrEqual(address a, address b)
    ((b != 0) && (a != 0) && (a != b) &&
    
    /// delegateIsGreaterOrEqual(a, b);
    /// if a is delegated to b, and b is delegated to b, then b should have at least as many votes as a
    
    ((delegates(a) == b) && (delegates(b) == b)) => to_mathint(getVotes(b)) >= balanceOf(a) + balanceOf(b) &&
    /// both delegated to a, then the delegate (a) should have sum of votes of both delegators balance at minimum
    ((delegates(a) == a) && (delegates(b) == a)) => to_mathint(getVotes(a)) >= balanceOf(a) + balanceOf(b) &&
    /// delegated to the same address, then the delegate should have sum of votes of both delegators balance at minimum
    (delegates(a) == delegates(b)) => to_mathint(getVotes(delegates(b))) >= balanceOf(a) + balanceOf(b))

     {
        preserved {
            requireInvariant corretCheckpoints(a);
            requireInvariant corretCheckpoints(b);
            requireInvariant delegateIsGreaterOrEqual(a, b);
            requireInvariant delegateIsGreaterOrEqual(b, a);
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant userVotesLteTotalSupply(a);
            requireInvariant mirrorIsTrue(a);
            requireInvariant mirrorIsTrue(b);
            requireInvariant addressZeroCannotDelegate();
        }
    }


invariant checkPointsLtTimestampMax(address a)
    to_mathint(numCheckpoints(a)) <= to_mathint(timestampMax()) {
        preserved {
            require to_mathint(numCheckpoints(a)) <= timestampMax() - 1;
        }
    }
/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: userVotes is less than or equal to the max total supply                                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant userVotesLteTotalSupply(address user)
    getVotes(user) <= totalSupply() {
        preserved burn(address to, uint256 amount) with (env e) {
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant mirrorIsTrue(to);
        }
    }

invariant twoUserVotesLteTotalSupply(address usera, address userb)
    to_mathint(getVotes(usera)) + to_mathint(getVotes(userb)) <= to_mathint(totalSupply()) {
        preserved {
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant mirrorIsTrue(usera);
            requireInvariant mirrorIsTrue(userb);
        }
    }

invariant addressZeroCannotDelegate()
    delegates(0) == 0 {
        preserved delegate(address to) with (env e) {
            require(e.msg.sender != 0);
        }
    }

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: maxSupply is equal to the max total supply                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant maxSupplyEqMAXSUPPLY()
    maxSupply() == MAX_SUPPLY();

/// no state changes you could ever make that would put the total supply above the max supply
invariant totalSupplyLteUint224Max()
    totalSupply() <= balanceMax() {
        preserved burn(address to, uint256 amount) with (env e) {
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant mirrorIsTrue(to);
        }
    }

/// hmmm, I wish I could pull the totalSupply this block directly from the token contract
/// TODO: fix this once I get the ghost figured out
/// seems like I need to make a mapping and global ghost variable to track the total supply
/// stored in the ERC20Votes contract https://docs.certora.com/en/latest/docs/confluence/map/ghosts.html
invariant getPastTotalSupplyEqTotalSupply(env e)
    getPastTotalSupply(e, assert_uint256(e.block.timestamp - 1)) == totalSupply() {
        preserved {
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant mirrorIsTrue(e.msg.sender);
        }
    }

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: balance of address(0) is 0                                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant zeroAddressNoBalance()
    balanceOf(0) == 0;

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: balance of well address is always 0                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant wellAddressNoBalance()
    balanceOf(xWELLAddress()) == 0;

rule userCanDelegateBalance(env e, address to) {
    address from = e.msg.sender;
    require to != 0 && from != 0; /// moving votes to address 0 does not register
    require(delegates(from) != to); /// not already delegated to the target address
    requireInvariant mirrorIsTrue(from);
    requireInvariant mirrorIsTrue(to);
    requireInvariant doubleDelegateIsGreaterOrEqual(from, to);
    requireInvariant corretCheckpoints(from);
    requireInvariant corretCheckpoints(to);

    mathint startingVotes = to_mathint(getVotes(to));
    mathint fromBalance = to_mathint(balanceOf(from));

    delegate(e, to);

    mathint endingVotes = to_mathint(getVotes(to));

    assert fromBalance != 0 => endingVotes == startingVotes + fromBalance, "balance not delegated";
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: only mint and burn can change total supply                                                                   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule noChangeTotalSupply(env e) {
    requireInvariant totalSupplyIsSumOfBalances();

    method f;
    calldataarg args;

    uint256 totalSupplyBefore = totalSupply();
    f(e, args);
    uint256 totalSupplyAfter = totalSupply();

    assert totalSupplyAfter > totalSupplyBefore => f.selector == sig:mint(address,uint256).selector;
    assert totalSupplyAfter < totalSupplyBefore => f.selector == sig:burn(address,uint256).selector;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: only the token holder or an approved third party can reduce an account's balance                             │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule onlyAuthorizedCanTransfer(env e) {
    requireInvariant totalSupplyIsSumOfBalances();

    method f;
    calldataarg args;
    address account;

    uint256 allowanceBefore = allowance(account, e.msg.sender);
    uint256 balanceBefore   = balanceOf(account);
    f(e, args);
    uint256 balanceAfter    = balanceOf(account);

    assert (
        balanceAfter < balanceBefore
    ) => (
        f.selector == sig:burn(address,uint256).selector ||
        e.msg.sender == account ||
        balanceBefore - balanceAfter <= to_mathint(allowanceBefore)
    );
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: only the token holder (or a permit) can increase allowance. The spender can decrease it by using it          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule onlyHolderOfSpenderCanChangeAllowance(env e) {
    requireInvariant totalSupplyIsSumOfBalances();

    method f;
    calldataarg args;
    address holder;
    address spender;

    uint256 allowanceBefore = allowance(holder, spender);
    f(e, args);
    uint256 allowanceAfter = allowance(holder, spender);

    assert (
        allowanceAfter > allowanceBefore
    ) => (
        (f.selector == sig:approve(address,uint256).selector           && e.msg.sender == holder) ||
        (f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector) ||
        (f.selector == sig:increaseAllowance(address,uint256).selector && e.msg.sender == holder)
    );

    assert (
        allowanceAfter < allowanceBefore
    ) => (
        (f.selector == sig:transferFrom(address,address,uint256).selector && e.msg.sender == spender) ||
        (f.selector == sig:approve(address,uint256).selector              && e.msg.sender == holder ) ||
        (f.selector == sig:decreaseAllowance(address,uint256).selector    && e.msg.sender == holder ) ||
        (f.selector == sig:burn(address,uint256).selector                                           ) || /// burn decreases allowance
        (f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector)
    );
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: mint behavior and side effects                                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule mint(env e, uint256 amount, address to, address other) {
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant addressZeroCannotDelegate(); /// if address 0 has a delegate, it causes problems here

    require nonpayable(e);
    require(e.block.timestamp <= timestampMax());

    /// other must be different than to and from
    // require(to != e.msg.sender && to != other);
    requireInvariant delegateIsGreaterOrEqualBalanceIndividual(to);

    // cache state
    uint256 toBalanceBefore    = balanceOf(to);
    uint256 toVotesBefore      = getVotes(to);
    uint256 otherBalanceBefore = balanceOf(other);
    uint256 totalSupplyBefore  = totalSupply();

    // run transaction
    mint(e, to, amount);

    // updates balance and totalSupply
    assert to_mathint(balanceOf(to)) == toBalanceBefore   + amount;
    assert to_mathint(totalSupply()) == totalSupplyBefore + amount;

    // no other balance is modified
    assert balanceOf(other) != otherBalanceBefore => other == to;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: burn behavior and side effects                                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule burn(env e) {
    requireInvariant totalSupplyIsSumOfBalances();
    require nonpayable(e);
    require(e.block.timestamp <= timestampMax()); /// timestamp sanity check
    require(bufferCap(e.msg.sender) >= buffer(e, e.msg.sender));
    require(to_mathint(midPoint(e.msg.sender)) == to_mathint(bufferCap(e.msg.sender)) / 2);
    require(e.msg.sender != 0); /// filter out zero address

    address from;
    address other;
    uint256 amount;

    // cache state
    uint256 fromBalanceBefore  = balanceOf(from);
    uint256 otherBalanceBefore = balanceOf(other);
    uint256 totalSupplyBefore  = totalSupply();

    require(allowance(from, e.msg.sender) >= amount);
    require(amount != 0);

    // run transaction
    burn(e, from, amount);

    // updates balance and totalSupply
    assert to_mathint(balanceOf(from)) == fromBalanceBefore   - amount;
    assert to_mathint(totalSupply())   == totalSupplyBefore - amount;

    // no other balance is modified
    assert balanceOf(other) != otherBalanceBefore => other == from;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: transfer behavior and side effects                                                                            │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule transfer(env e) {
    requireInvariant totalSupplyIsSumOfBalances();

    require nonpayable(e);
    require(e.block.timestamp <= timestampMax());

    address holder = e.msg.sender;
    address recipient;
    address other;
    uint256 amount;

    requireInvariant mirrorIsTrue(holder);
    requireInvariant mirrorIsTrue(recipient);
    requireInvariant balanceOfLteUint224Max(holder);
    requireInvariant balanceOfLteUint224Max(recipient);

    requireInvariant delegateIsGreaterOrEqualBalanceIndividual(holder);
    requireInvariant delegateIsGreaterOrEqualBalanceIndividual(recipient);

    // cache state
    uint256 holderBalanceBefore          = balanceOf(holder);
    uint256 recipientVotesBefore         = getVotes(recipient);
    uint256 recipientDelegateVotesBefore = getVotes(delegates(recipient));
    uint256 recipientBalanceBefore       = balanceOf(recipient);
    uint256 otherBalanceBefore           = balanceOf(other);

    // run transaction
    transfer@withrevert(e, recipient, amount);

    /// if holder delegated their votes, ensure the delegatee's vote counts are greater than
    /// or equal to the holder's balances

    // check outcome
    if (lastReverted) {
        assert holder == 0 || /// fails when holder is address 0
        recipient == 0 || /// fails when recipient is address 0
        amount > holderBalanceBefore || /// fails when holder has not enough balance to transfer
        recipient == xWELLAddress() || /// fails when transfering to xWELL
        to_mathint(recipientBalanceBefore) + to_mathint(amount) > to_mathint(balanceMax()) || /// balance max failure
        recipientDelegateVotesBefore + amount > to_mathint(balanceMax()); /// votes max failure overflow -> safecast to 224 failure
    } else {
        // balances of holder and recipient are updated
        assert to_mathint(balanceOf(holder))    == holderBalanceBefore    - (holder == recipient ? 0 : amount);
        assert to_mathint(balanceOf(recipient)) == recipientBalanceBefore + (holder == recipient ? 0 : amount);

        // no other balance is modified
        assert balanceOf(other) != otherBalanceBefore => (other == holder || other == recipient);
    }
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: transferFrom behavior and side effects                                                                        │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule transferFrom(env e, address holder, address recipient, address other, uint256 amount) {
    address spender = e.msg.sender;

    requireInvariant mirrorIsTrue(holder);
    requireInvariant mirrorIsTrue(recipient);

    requireInvariant totalSupplyIsSumOfBalances();
    require nonpayable(e);
    require(e.block.timestamp <= timestampMax());
    require(other != recipient && other != holder && other != spender);

    requireInvariant delegateIsGreaterOrEqualBalanceIndividual(holder);
    requireInvariant delegateIsGreaterOrEqualBalanceIndividual(recipient);

    /// if holder delegated their votes, ensure the delegatee's vote counts are greater than
    /// or equal to the holder's balances

    // cache state
    uint256 allowanceBefore              = allowance(holder, spender);
    uint256 holderBalanceBefore          = balanceOf(holder);
    uint256 recipientBalanceBefore       = balanceOf(recipient);
    uint256 otherBalanceBefore           = balanceOf(other);
    uint256 recipientDelegateVotesBefore = getVotes(delegates(recipient));

    // run transaction
    transferFrom@withrevert(e, holder, recipient, amount);

    // check outcome
    if (lastReverted) {
        assert holder == 0 ||
        recipient == 0 ||
        spender == 0 ||
        amount > holderBalanceBefore ||
        amount > allowanceBefore ||
        recipient == xWELLAddress() ||
        to_mathint(recipientDelegateVotesBefore) + to_mathint(amount) > to_mathint(balanceMax()) ||
        to_mathint(recipientBalanceBefore) + to_mathint(amount) > to_mathint(balanceMax());
    } else {
        // allowance is valid & updated
        assert allowanceBefore            >= amount;
        assert to_mathint(allowance(holder, spender)) == (allowanceBefore == max_uint256 ? max_uint256 : allowanceBefore - amount);

        // balances of holder and recipient are updated
        assert to_mathint(balanceOf(holder))    == holderBalanceBefore    - (holder == recipient ? 0 : amount);
        assert to_mathint(balanceOf(recipient)) == recipientBalanceBefore + (holder == recipient ? 0 : amount);

        // no other balance is modified
        assert balanceOf(other) == otherBalanceBefore;
    }
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: approve behavior and side effects                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule approve(env e) {
    require nonpayable(e);

    address holder = e.msg.sender;
    address spender;
    address otherHolder;
    address otherSpender;
    uint256 amount;

    // cache state
    uint256 otherAllowanceBefore = allowance(otherHolder, otherSpender);

    // run transaction
    approve@withrevert(e, spender, amount);

    // check outcome
    if (lastReverted) {
        assert holder == 0 || spender == 0;
    } else {
        // allowance is updated
        assert allowance(holder, spender) == amount;

        // other allowances are untouched
        assert allowance(otherHolder, otherSpender) != otherAllowanceBefore => (otherHolder == holder && otherSpender == spender);
    }
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: permit behavior and side effects                                                                              │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule permit(env e) {
    require nonpayable(e);

    address holder;
    address spender;
    uint256 amount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;

    address account1;
    address account2;
    address account3;

    // cache state
    uint256 nonceBefore          = nonces(holder);
    uint256 otherNonceBefore     = nonces(account1);
    uint256 otherAllowanceBefore = allowance(account2, account3);

    // sanity: nonce overflow, which possible in theory, is assumed to be impossible in practice
    require nonceBefore      < max_uint256;
    require otherNonceBefore < max_uint256;

    // run transaction
    permit@withrevert(e, holder, spender, amount, deadline, v, r, s);

    // check outcome
    if (lastReverted) {
        // Without formally checking the signature, we can't verify exactly the revert causes
        assert true;
    } else {
        // allowance and nonce are updated
        assert allowance(holder, spender) == amount;
        assert to_mathint(nonces(holder)) == nonceBefore + 1;

        // deadline was respected
        assert deadline >= e.block.timestamp;

        // no other allowance or nonce is modified
        assert nonces(account1)              != otherNonceBefore     => account1 == holder;
        assert allowance(account2, account3) != otherAllowanceBefore => (account2 == holder && account3 == spender);
    }
}
