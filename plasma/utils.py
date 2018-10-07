from ethereum import utils as u
#from .constants import NULL_HASH
from signatures import sign
from fixed_merkle import FixedMerkle

NULL_BYTE = b'\x00'
NULL_HASH = NULL_BYTE * 32
NULL_SIGNATURE = NULL_BYTE * 65
NULL_ADDRESS = NULL_BYTE * 20
NULL_ADDRESS_HEX = '0x' + NULL_ADDRESS.hex()

def get_empty_merkle_tree_hash(depth):
    zeroes_hash = NULL_HASH
    for _ in range(depth):
        zeroes_hash = u.sha3(zeroes_hash + zeroes_hash)
    return zeroes_hash


def get_merkle_of_leaves(depth, leaves):
    return FixedMerkle(depth, leaves)


def bytes_fill_left(inp, length):
    return bytes(length - len(inp)) + inp


def get_deposit_hash(owner, token, value):
    return u.sha3(owner + token + b'\x00' * 31 + u.int_to_bytes(value))


def confirm_tx(tx, root, key):
    return sign(u.sha3(tx.hash + root), key)
