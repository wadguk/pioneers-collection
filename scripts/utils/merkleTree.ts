import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

export const accessList = [
    ["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", 250],
    ["0x6A219Ec4A7759A7B25F1f76a8711f3Bb655CA8d7", 250],
    ["0x70997970C51812dc3A010C7d01b50e0d17dc79C8", 250],
    ["0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", 250],
    ["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", 250],
    ["0xA1b24778EB2BFF1E7053fD5f3f7da124464849d1", 250],
]

export const merkleTree = StandardMerkleTree.of(accessList, ["address", "uint256"])
export const root = merkleTree.root;
export const proof = merkleTree.getProof(0);
export const secondProof = merkleTree.getProof(1);
export const thirdProof = merkleTree.getProof(2);

export const generateMerkleTree = (leaves: any): string => {
    const merkleTree = StandardMerkleTree.of(leaves, ["address", "uint256"]);
    return merkleTree.root;
};
