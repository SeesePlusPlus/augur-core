pragma solidity 0.4.18;

import 'reporting/IDisputeCrowdsourcer.sol';
import 'libraries/token/VariableSupplyToken.sol';
import 'reporting/BaseReportingParticipant.sol';
import 'libraries/Initializable.sol';
import 'libraries/DelegationTarget.sol';
import 'libraries/Extractable.sol';


contract DisputeCrowdsourcer is DelegationTarget, VariableSupplyToken, Extractable, BaseReportingParticipant, IDisputeCrowdsourcer, Initializable {
    function initialize(IMarket _market, uint256 _size, bytes32 _payoutDistributionHash, uint256[] _payoutNumerators, bool _invalid) public onlyInGoodTimes beforeInitialized returns (bool) {
        endInitialization();
        market = _market;
        reputationToken = market.getReputationToken();
        feeWindow = market.getFeeWindow();
        cash = market.getDenominationToken();
        size = _size;
        payoutNumerators = _payoutNumerators;
        payoutDistributionHash = _payoutDistributionHash;
        invalid = _invalid;
        return true;
    }

    function redeem(address _redeemer) public onlyInGoodTimes returns (bool) {
        require(isDisavowed() || market.getWinningPayoutDistributionHash() == getPayoutDistributionHash());
        redeemForAllFeeWindows();
        uint256 _reputationSupply = reputationToken.balanceOf(this);
        uint256 _cashSupply = cash.balanceOf(this);
        uint256 _amount = balances[_redeemer];
        uint256 _feeShare = _cashSupply * _amount / supply;
        uint256 _reputationShare = _reputationSupply * _amount / supply;
        burn(_redeemer, _amount);
        reputationToken.transfer(_redeemer, _reputationShare);
        cash.withdrawEtherTo(_redeemer, _feeShare);
        return true;
    }

    function contribute(address _participant, uint256 _amount) public onlyInGoodTimes returns (bool) {
        require(IMarket(msg.sender) == market);
        _amount = _amount.min(size - totalSupply());
        if (_amount == 0) {
            return true;
        }
        market.getReputationToken().trustedReportingParticipantTransfer(_participant, this, _amount);
        feeWindow.mintFeeTokens(_amount);
        mint(_participant, _amount);
        if (totalSupply() == size) {
            market.finishedCrowdsourcingDisputeBond();
        }
        return true;
    }

    function fork() public onlyInGoodTimes returns (bool) {
        require(market == market.getUniverse().getForkingMarket());
        IUniverse _newUniverse = market.getUniverse().createChildUniverse(payoutDistributionHash);
        IReputationToken _reputationToken = market.getReputationToken();
        IReputationToken _newReputationToken = _newUniverse.getReputationToken();
        redeemForAllFeeWindows();
        uint256 _balance = _reputationToken.balanceOf(this);
        _reputationToken.migrateOut(_newReputationToken, _balance);
        _newReputationToken.mintForDisputeCrowdsourcer(_balance);
        // by removing the market, the token will become disavowed and therefore users can remove freely
        reputationToken = _newReputationToken;
        market = IMarket(0);
        return true;
    }

    function disavow() public onlyInGoodTimes returns (bool) {
        require(IMarket(msg.sender) == market);
        market = IMarket(0);
        return true;
    }

    function getStake() public view returns (uint256) {
        return totalSupply();
    }

    function onTokenTransfer(address _from, address _to, uint256 _value) internal returns (bool) {
        controller.getAugur().logDisputeCrowdsourcerTokensTransferred(market.getUniverse(), _from, _to, _value);
        return true;
    }

    function onMint(address _target, uint256 _amount) internal returns (bool) {
        controller.getAugur().logDisputeCrowdsourcerTokensMinted(market.getUniverse(), _target, _amount);
        return true;
    }

    function onBurn(address _target, uint256 _amount) internal returns (bool) {
        if (isDisavowed()) {
            return true;
        }
        controller.getAugur().logDisputeCrowdsourcerTokensBurned(market.getUniverse(), _target, _amount);
        return true;
    }

    function getFeeWindow() public view returns (IFeeWindow) {
        return feeWindow;
    }

    function getReputationToken() public view returns (IReputationToken) {
        return reputationToken;
    }

    function getProtectedTokens() internal returns (address[] memory) {
        address[] memory _protectedTokens = new address[](2);
        _protectedTokens[0] = feeWindow;
        _protectedTokens[1] = market.getReputationToken();
        return _protectedTokens;
    }
}
