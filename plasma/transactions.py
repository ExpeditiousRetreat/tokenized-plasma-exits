from transaction import Transaction
#from .constants import NULL_ADDRESS


BLKNUM_OFFSET = 1000000000
TXINDEX_OFFSET = 10000

NULL_BYTE = b'\x00'
NULL_HASH = NULL_BYTE * 32
NULL_SIGNATURE = NULL_BYTE * 65
NULL_ADDRESS = NULL_BYTE * 20
NULL_ADDRESS_HEX = '0x' + NULL_ADDRESS.hex()

def decode_utxo_id(utxo_id):
    blknum = utxo_id // BLKNUM_OFFSET
    txindex = (utxo_id % BLKNUM_OFFSET) // BLKNUM_OFFSET
    oindex = utxo_id - blknum * BLKNUM_OFFSET - txindex * TXINDEX_OFFSET
    return (blknum, txindex, oindex)


def encode_utxo_id(blknum, txindex, oindex):
    return (blknum * BLKNUM_OFFSET) + (txindex * TXINDEX_OFFSET) + (oindex * 1)


def decode_tx_id(utxo_id):
    (blknum, txindex, _) = decode_utxo_id(utxo_id)
    return encode_utxo_id(blknum, txindex, 0)


def get_deposit_tx(owner, amount):
    return Transaction(0, 0, 0,
                       0, 0, 0,
                       NULL_ADDRESS,
                       owner, amount,
                       NULL_ADDRESS, 0)
