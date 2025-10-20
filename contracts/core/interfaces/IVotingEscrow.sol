// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IVotingEscrow {
    function artProxy() external returns (address);
    function team() external returns (address);

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @return TokenId of created veNFT
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256);

    function lockPermanent(uint256 _tokenId) external;

    function setTeam(address _team) external;

    function toggleSplit(address _account, bool _bool) external;

    function setArtProxy(address _proxy) external;
    function canSplit(address _account) external view returns (bool);
}
