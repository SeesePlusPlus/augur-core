pragma solidity 0.4.18;


import 'reporting/IParticipationToken.sol';
import 'libraries/DelegationTarget.sol';
import 'libraries/ITyped.sol';
import 'libraries/Initializable.sol';
import 'reporting/IReputationToken.sol';
import 'reporting/IReportingWindow.sol';
import 'libraries/math/SafeMathUint256.sol';
import 'TEST/MockVariableSupplyToken.sol';


contract MockParticipationToken is ITyped, Initializable, MockVariableSupplyToken, IParticipationToken {
    using SafeMathUint256 for uint256;

    IReportingWindow private initializeReportingWindowValue;
    IReportingWindow private setReportingWindowValue;
    uint256 private buyValue;
    bool private redeemForgoFeesValue;

    function getInitializeReportingWindow() public returns (IReportingWindow) {
        return initializeReportingWindowValue;
    }

    function setReportingWindow(IReportingWindow _reportingWindow) public {
        setReportingWindowValue = _reportingWindow;
    }

    function getBuyValue() public returns(uint256) {
        return buyValue;
    }

    function getRedeemForgoFeesValue() public returns(bool) {
        return redeemForgoFeesValue;
    }

    function buy(uint256 _attotokens) public afterInitialized returns (bool) {
        buyValue = _attotokens;
        return true;
    }

    function redeem(bool forgoFees) public afterInitialized returns (bool) {
        redeemForgoFeesValue = forgoFees;
        return true;
    }

    function callIncreaseTotalWinningStake(IReportingWindow _reportingWindow, uint256 _attotokens) public returns (bool) {
        return _reportingWindow.increaseTotalWinningStake(_attotokens);
    }

    function callCollectParticipationTokenReportingFees(IReportingWindow _reportingWindow, address _reporterAddress, uint256 _attoStake, bool _forgoFees) public returns(uint256) {
        return _reportingWindow.collectParticipationTokenReportingFees(_reporterAddress, _attoStake, _forgoFees);
    }

    function callTrustedParticipationTokenTransfer(IReputationToken _reputationToken, address _source, address _destination, uint256 _attotokens) public returns (bool) {
        return _reputationToken.trustedParticipationTokenTransfer(_source, _destination, _attotokens);
    }

    function getTypeName() public view returns (bytes32) {
        return "ParticipationToken";
    }

    function initialize(IReportingWindow _reportingWindow) public returns (bool) {
        endInitialization();
        initializeReportingWindowValue = _reportingWindow;
        return true;
    }

    function getReportingWindow() public view returns (IReportingWindow) {
        return setReportingWindowValue;
    }

    function redeemForHolder(address _sender, bool forgoFees) public returns (bool) {
        return true;
    }
}
