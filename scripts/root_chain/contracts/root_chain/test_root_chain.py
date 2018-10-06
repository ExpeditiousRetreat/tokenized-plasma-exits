import pytest
import rlp
from plasma_core.transaction import Transaction, UnsignedTransaction
from plasma_core.utils.merkle.fixed_merkle import FixedMerkle
from plasma_core.utils.utils import confirm_tx, get_deposit_hash
from plasma_core.utils.transactions import encode_utxo_id, decode_utxo_id
from plasma_core.constants import NULL_ADDRESS, NULL_ADDRESS_HEX


@pytest.fixture
def root_chain(t, get_contract):
    contract = get_contract('RootChain')
    t.chain.mine()
    return contract


def test_deposit(t, u, root_chain):
    owner, value_1 = t.a0, 100
    blknum = root_chain.getDepositBlock()
    root_chain.deposit(value=value_1)
    assert root_chain.getPlasmaBlock(blknum)[0] == u.sha3(owner + b'\x00' * 31 + NULL_ADDRESS + u.int_to_bytes(value_1))
    assert root_chain.getPlasmaBlock(blknum)[1] == t.chain.head_state.timestamp
    assert root_chain.getDepositBlock() == blknum + 1


def test_start_deposit_exit(t, u, root_chain, assert_tx_failed):
    two_weeks = 60 * 60 * 24 * 7 * 2
    value_1 = 100
    # Deposit once to make sure everything works for deposit block
    root_chain.deposit(value=value_1)
    blknum = root_chain.getDepositBlock()
    root_chain.deposit(value=value_1)
    expected_utxo_pos = encode_utxo_id(blknum, 0, 0)
    expected_exitable_at = t.chain.head_state.timestamp + two_weeks
    exit_bond = root_chain.EXIT_BOND()
    root_chain.startDepositExit(expected_utxo_pos, NULL_ADDRESS, value_1, value=exit_bond)
    exitable_at, utxo_pos = root_chain.getNextExit(NULL_ADDRESS)
    assert utxo_pos == expected_utxo_pos
    assert exitable_at == expected_exitable_at
    assert root_chain.exits(utxo_pos) == ['0x82a978b3f5962a5b0957d9ee9eef472ee55b42f1', NULL_ADDRESS_HEX, 100]
    # Same deposit cannot be exited twice
    assert_tx_failed(lambda: root_chain.startDepositExit(utxo_pos, NULL_ADDRESS, value_1, value=exit_bond))
    # Fails if transaction sender is not the depositor
    assert_tx_failed(lambda: root_chain.startDepositExit(utxo_pos, NULL_ADDRESS, value_1, sender=t.k1, value=exit_bond))
    # Fails if utxo_pos is wrong
    assert_tx_failed(lambda: root_chain.startDepositExit(utxo_pos * 2, NULL_ADDRESS, value_1, value=exit_bond))
    # Fails if value given is not equal to deposited value
    assert_tx_failed(lambda: root_chain.startDepositExit(utxo_pos, NULL_ADDRESS, value_1 + 1, value=exit_bond))


def test_start_fee_exit(t, u, root_chain, assert_tx_failed):
    two_weeks = 60 * 60 * 24 * 7 * 2
    value_1 = 100
    blknum = root_chain.getDepositBlock()
    root_chain.deposit(value=value_1)
    expected_utxo_pos = root_chain.currentFeeExit()
    expected_exitable_at = t.chain.head_state.timestamp + two_weeks + 1
    assert root_chain.currentFeeExit() == 1
    exit_bond = root_chain.EXIT_BOND()
    root_chain.startFeeExit(NULL_ADDRESS, 1, value=exit_bond)
    assert root_chain.currentFeeExit() == 2
    exitable_at, utxo_pos = root_chain.getNextExit(NULL_ADDRESS)
    fee_priority = exitable_at << 128 | utxo_pos
    assert utxo_pos == expected_utxo_pos
    assert exitable_at == expected_exitable_at

    expected_utxo_pos = encode_utxo_id(blknum, 0, 0)
    root_chain.startDepositExit(expected_utxo_pos, NULL_ADDRESS, value_1, value=exit_bond)
    created_at, utxo_pos = root_chain.getNextExit(NULL_ADDRESS)
    deposit_priority = created_at << 128 | utxo_pos
    assert fee_priority > deposit_priority
    # Fails if transaction sender isn't the authority
    assert_tx_failed(lambda: root_chain.startFeeExit(NULL_ADDRESS, 1, sender=t.k1, value=exit_bond))


def test_start_exit(t, root_chain, assert_tx_failed):
    week_and_a_half = 60 * 60 * 24 * 13
    owner, value_1, key = t.a1, 100, t.k1
    tx1 = Transaction(0, 0, 0, 0, 0, 0,
                      NULL_ADDRESS,
                      owner, value_1, NULL_ADDRESS, 0)
    deposit_tx_hash = get_deposit_hash(owner, NULL_ADDRESS, value_1)
    dep_blknum = root_chain.getDepositBlock()
    assert dep_blknum == 1
    root_chain.deposit(value=value_1, sender=key)
    merkle = FixedMerkle(16, [deposit_tx_hash], True)
    proof = merkle.create_membership_proof(deposit_tx_hash)
    confirmSig1 = confirm_tx(tx1, root_chain.getPlasmaBlock(dep_blknum)[0], key)
    snapshot = t.chain.snapshot()
    sigs = tx1.sig1 + tx1.sig2 + confirmSig1
    utxoId = encode_utxo_id(dep_blknum, 0, 0)
    # Deposit exit
    exit_bond = root_chain.EXIT_BOND()
    root_chain.startDepositExit(utxoId, NULL_ADDRESS, tx1.amount1, sender=key, value=exit_bond)

    t.chain.head_state.timestamp += week_and_a_half
    # Cannot exit twice off of the same utxo
    utxo_pos1 = encode_utxo_id(dep_blknum, 0, 0)
    assert_tx_failed(lambda: root_chain.startExit(utxo_pos1, deposit_tx_hash, proof, sigs, sender=key, value=exit_bond))
    assert root_chain.getExit(utxo_pos1) == ['0x' + owner.hex(), NULL_ADDRESS_HEX, 100]
    t.chain.revert(snapshot)

    tx2 = Transaction(dep_blknum, 0, 0, 0, 0, 0,
                      NULL_ADDRESS,
                      owner, value_1, NULL_ADDRESS, 0)
    tx2.sign1(key)
    tx_bytes2 = rlp.encode(tx2, UnsignedTransaction)
    merkle = FixedMerkle(16, [tx2.merkle_hash], True)
    proof = merkle.create_membership_proof(tx2.merkle_hash)
    child_blknum = root_chain.currentChildBlock()
    assert child_blknum == 1000
    root_chain.submitBlock(merkle.root)
    confirmSig1 = confirm_tx(tx2, root_chain.getPlasmaBlock(child_blknum)[0], key)
    sigs = tx2.sig1 + tx2.sig2 + confirmSig1
    snapshot = t.chain.snapshot()
    # # Single input exit
    utxo_pos2 = encode_utxo_id(child_blknum, 0, 0)
    root_chain.startExit(utxo_pos2, tx_bytes2, proof, sigs, sender=key, value=exit_bond)
    assert root_chain.getExit(utxo_pos2) == ['0x' + owner.hex(), NULL_ADDRESS_HEX, 100]
    t.chain.revert(snapshot)
    dep2_blknum = root_chain.getDepositBlock()
    assert dep2_blknum == 1001
    root_chain.deposit(value=value_1, sender=key)
    tx3 = Transaction(child_blknum, 0, 0, dep2_blknum, 0, 0,
                      NULL_ADDRESS,
                      owner, value_1, NULL_ADDRESS, 0, 0)
    tx3.sign1(key)
    tx3.sign2(key)
    tx_bytes3 = rlp.encode(tx3, UnsignedTransaction)
    merkle = FixedMerkle(16, [tx3.merkle_hash], True)
    proof = merkle.create_membership_proof(tx3.merkle_hash)
    child2_blknum = root_chain.currentChildBlock()
    assert child2_blknum == 2000
    root_chain.submitBlock(merkle.root)
    confirmSig1 = confirm_tx(tx3, root_chain.getPlasmaBlock(child2_blknum)[0], key)
    confirmSig2 = confirm_tx(tx3, root_chain.getPlasmaBlock(child2_blknum)[0], key)
    sigs = tx3.sig1 + tx3.sig2 + confirmSig1 + confirmSig2
    # Double input exit
    utxo_pos3 = encode_utxo_id(child2_blknum, 0, 0)
    root_chain.startExit(utxo_pos3, tx_bytes3, proof, sigs, sender=key, value=exit_bond)
    assert root_chain.getExit(utxo_pos3) == ['0x' + owner.hex(), NULL_ADDRESS_HEX, 100]


def test_challenge_exit(t, u, root_chain, assert_tx_failed):
    owner, value_1, key = t.a1, 100, t.k1
    tx1 = Transaction(0, 0, 0, 0, 0, 0,
                      NULL_ADDRESS,
                      owner, value_1, NULL_ADDRESS, 0)
    deposit_tx_hash = get_deposit_hash(owner, NULL_ADDRESS, value_1)
    utxo_pos1 = encode_utxo_id(root_chain.getDepositBlock(), 0, 0)
    root_chain.deposit(value=value_1, sender=key)
    utxo_pos2 = encode_utxo_id(root_chain.getDepositBlock(), 0, 0)
    root_chain.deposit(value=value_1, sender=key)
    merkle = FixedMerkle(16, [deposit_tx_hash], True)
    proof = merkle.create_membership_proof(deposit_tx_hash)
    confirmSig1 = confirm_tx(tx1, root_chain.getPlasmaBlock(utxo_pos1)[0], key)
    sigs = tx1.sig1 + tx1.sig2 + confirmSig1
    exit_bond = root_chain.EXIT_BOND()
    root_chain.startDepositExit(utxo_pos1, NULL_ADDRESS, tx1.amount1, sender=key, value=exit_bond)
    tx3 = Transaction(utxo_pos2, 0, 0, 0, 0, 0,
                      NULL_ADDRESS,
                      owner, value_1, NULL_ADDRESS, 0)
    tx3.sign1(key)
    tx_bytes3 = rlp.encode(tx3, UnsignedTransaction)
    merkle = FixedMerkle(16, [tx3.merkle_hash], True)
    proof = merkle.create_membership_proof(tx3.merkle_hash)
    child_blknum = root_chain.currentChildBlock()
    root_chain.submitBlock(merkle.root)
    confirmSig = confirm_tx(tx3, root_chain.getPlasmaBlock(child_blknum)[0], key)
    sigs = tx3.sig1 + tx3.sig2
    utxo_pos3 = encode_utxo_id(child_blknum, 0, 0)

    utxo1_blknum, _, _ = decode_utxo_id(utxo_pos1)
    tx4 = Transaction(utxo1_blknum, 0, 0, 0, 0, 0,
                      NULL_ADDRESS,
                      owner, value_1, NULL_ADDRESS, 0)
    tx4.sign1(key)
    tx_bytes4 = rlp.encode(tx4, UnsignedTransaction)
    merkle = FixedMerkle(16, [tx4.merkle_hash], True)
    proof = merkle.create_membership_proof(tx4.merkle_hash)
    child_blknum = root_chain.currentChildBlock()
    root_chain.submitBlock(merkle.root)
    confirmSig = confirm_tx(tx4, root_chain.getPlasmaBlock(child_blknum)[0], key)
    sigs = tx4.sig1 + tx4.sig2
    utxo_pos4 = encode_utxo_id(child_blknum, 0, 0)
    oindex1 = 0
    assert root_chain.exits(utxo_pos1) == ['0x' + owner.hex(), NULL_ADDRESS_HEX, 100]
    # Fails if transaction after exit doesn't reference the utxo being exited
    assert_tx_failed(lambda: root_chain.challengeExit(utxo_pos3, oindex1, tx_bytes3, proof, sigs, confirmSig))
    # Fails if transaction proof is incorrect
    assert_tx_failed(lambda: root_chain.challengeExit(utxo_pos4, oindex1, tx_bytes4, proof[::-1], sigs, confirmSig))
    # Fails if transaction confirmation is incorrect
    assert_tx_failed(lambda: root_chain.challengeExit(utxo_pos4, oindex1, tx_bytes4, proof, sigs, confirmSig[::-1]))
    root_chain.challengeExit(utxo_pos4, oindex1, tx_bytes4, proof, sigs, confirmSig)
    assert root_chain.exits(utxo_pos1) == [NULL_ADDRESS_HEX, NULL_ADDRESS_HEX, value_1]


def test_finalize_exits(t, u, root_chain):
    two_weeks = 60 * 60 * 24 * 14
    owner, value_1, key = t.a1, 100, t.k1
    tx1 = Transaction(0, 0, 0, 0, 0, 0,
                      NULL_ADDRESS,
                      owner, value_1, NULL_ADDRESS, 0)
    dep1_blknum = root_chain.getDepositBlock()
    root_chain.deposit(value=value_1, sender=key)
    utxo_pos1 = encode_utxo_id(dep1_blknum, 0, 0)
    exit_bond = root_chain.EXIT_BOND()
    root_chain.startDepositExit(utxo_pos1, NULL_ADDRESS, tx1.amount1, sender=key, value=exit_bond)
    t.chain.head_state.timestamp += two_weeks * 2
    assert root_chain.exits(utxo_pos1) == ['0x' + owner.hex(), NULL_ADDRESS_HEX, 100]
    pre_balance = t.chain.head_state.get_balance(owner)
    root_chain.finalizeExits(sender=t.k2)
    post_balance = t.chain.head_state.get_balance(owner)
    assert post_balance == pre_balance + value_1 + exit_bond
    assert root_chain.exits(utxo_pos1) == [NULL_ADDRESS_HEX, NULL_ADDRESS_HEX, value_1]
