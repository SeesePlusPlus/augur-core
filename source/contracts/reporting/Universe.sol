pragma solidity 0.4.18;


import 'reporting/IUniverse.sol';
import 'libraries/DelegationTarget.sol';
import 'libraries/ITyped.sol';
import 'libraries/Initializable.sol';
import 'factories/ReputationTokenFactory.sol';
import 'factories/ReportingWindowFactory.sol';
import 'factories/UniverseFactory.sol';
import 'reporting/IMarket.sol';
import 'reporting/IReputationToken.sol';
import 'reporting/IStakeToken.sol';
import 'reporting/IDisputeBond.sol';
import 'reporting/IReportingWindow.sol';
import 'reporting/Reporting.sol';
import 'reporting/IRepPriceOracle.sol';
import 'reporting/IParticipationToken.sol';
import 'reporting/IDisputeBond.sol';
import 'libraries/math/SafeMathUint256.sol';
import 'Augur.sol';
import 'libraries/Extractable.sol';


contract Universe is DelegationTarget, Extractable, ITyped, Initializable, IUniverse {
    using SafeMathUint256 for uint256;

    IUniverse private parentUniverse;
    bytes32 private parentPayoutDistributionHash;
    IReputationToken private reputationToken;
    IMarket private forkingMarket;
    uint256 private forkEndTime;
    uint256 private forkReputationGoal;
    mapping(uint256 => IReportingWindow) private reportingWindows;
    mapping(bytes32 => IUniverse) private childUniverses;
    uint256 private openInterestInAttoEth;
    // We increase and decrease this value seperate from the totalSupply as we do not want to count potentional infalitonary bonuses from the migration reward
    uint256 private repAvailableForExtraBondPayouts;

    mapping (address => uint256) private validityBondInAttoeth;
    mapping (address => uint256) private targetReporterGasCosts;
    mapping (address => uint256) private designatedReportStakeInAttoRep;
    mapping (address => uint256) private designatedReportNoShowBondInAttoRep;
    mapping (address => uint256) private shareSettlementFeeDivisor;

    function initialize(IUniverse _parentUniverse, bytes32 _parentPayoutDistributionHash) external onlyInGoodTimes beforeInitialized returns (bool) {
        endInitialization();
        parentUniverse = _parentUniverse;
        parentPayoutDistributionHash = _parentPayoutDistributionHash;
        reputationToken = ReputationTokenFactory(controller.lookup("ReputationTokenFactory")).createReputationToken(controller, this);
        require(reputationToken != address(0));
        return true;
    }

    function fork() public onlyInGoodTimes afterInitialized returns (bool) {
        require(forkingMarket == address(0));
        require(isContainerForMarket(IMarket(msg.sender)));
        forkingMarket = IMarket(msg.sender);
        forkEndTime = controller.getTimestamp() + Reporting.getForkDurationSeconds();
        // We pre calculate the amount of REP needed to determine a winner early in a fork. We assume maximum possible fork inflation in every fork so this is hard to achieve with every subsequent fork and may become impossible in some universes.
        if (parentUniverse != IUniverse(0)) {
            uint256 _previousForkReputationGoal = parentUniverse.getForkReputationGoal();
            forkReputationGoal = _previousForkReputationGoal + (_previousForkReputationGoal / Reporting.getForkMigrationPercentageBonusDivisor());
        } else {
            // We're using a hardcoded supply value instead of getting the total REP supply from the token since at launch we will start out with a 0 supply token and users will migrate legacy REP to this token. Since the first fork may occur before all REP migrates we want to count that unmigrated REP too since it may participate in the fork eventually.
            forkReputationGoal = Reporting.getInitialREPSupply() / Reporting.getForkRepMigrationVictoryDivisor();
        }
        controller.getAugur().logUniverseForked();
        return true;
    }

    function getTypeName() public view returns (bytes32) {
        return "Universe";
    }

    function getParentUniverse() public view returns (IUniverse) {
        return parentUniverse;
    }

    function getParentPayoutDistributionHash() public view returns (bytes32) {
        return parentPayoutDistributionHash;
    }

    function getReputationToken() public view returns (IReputationToken) {
        return reputationToken;
    }

    function getForkingMarket() public view returns (IMarket) {
        return forkingMarket;
    }

    function getForkEndTime() public view returns (uint256) {
        return forkEndTime;
    }

    function getForkReputationGoal() public view returns (uint256) {
        return forkReputationGoal;
    }

    function getReportingWindow(uint256 _reportingWindowId) public view returns (IReportingWindow) {
        return reportingWindows[_reportingWindowId];
    }

    function getChildUniverse(bytes32 _parentPayoutDistributionHash) public view returns (IUniverse) {
        return childUniverses[_parentPayoutDistributionHash];
    }

    function getReportingWindowId(uint256 _timestamp) public view returns (uint256) {
        return _timestamp / getReportingPeriodDurationInSeconds();
    }

    function getReportingPeriodDurationInSeconds() public view returns (uint256) {
        return Reporting.getReportingDurationSeconds() + Reporting.getReportingDisputeDurationSeconds();
    }

    function getOrCreateReportingWindowByTimestamp(uint256 _timestamp) public onlyInGoodTimes returns (IReportingWindow) {
        uint256 _windowId = getReportingWindowId(_timestamp);
        if (reportingWindows[_windowId] == address(0)) {
            reportingWindows[_windowId] = ReportingWindowFactory(controller.lookup("ReportingWindowFactory")).createReportingWindow(controller, this, _windowId);
        }
        return reportingWindows[_windowId];
    }

    function getReportingWindowByTimestamp(uint256 _timestamp) public view onlyInGoodTimes returns (IReportingWindow) {
        uint256 _windowId = getReportingWindowId(_timestamp);
        return reportingWindows[_windowId];
    }

    function getOrCreateReportingWindowByMarketEndTime(uint256 _endTime) public onlyInGoodTimes returns (IReportingWindow) {
        return getOrCreateReportingWindowByTimestamp(_endTime + Reporting.getDesignatedReportingDurationSeconds() + Reporting.getDesignatedReportingDisputeDurationSeconds() + 1 + getReportingPeriodDurationInSeconds());
    }

    function getReportingWindowByMarketEndTime(uint256 _endTime) public view onlyInGoodTimes returns (IReportingWindow) {
        return getReportingWindowByTimestamp(_endTime + Reporting.getDesignatedReportingDurationSeconds() + Reporting.getDesignatedReportingDisputeDurationSeconds() + 1 + getReportingPeriodDurationInSeconds());
    }

    function getOrCreatePreviousReportingWindow() public onlyInGoodTimes returns (IReportingWindow) {
        return getOrCreateReportingWindowByTimestamp(controller.getTimestamp() - getReportingPeriodDurationInSeconds());
    }

    function getPreviousReportingWindow() public view onlyInGoodTimes returns (IReportingWindow) {
        return getReportingWindowByTimestamp(controller.getTimestamp() - getReportingPeriodDurationInSeconds());
    }

    function getOrCreateCurrentReportingWindow() public onlyInGoodTimes returns (IReportingWindow) {
        return getOrCreateReportingWindowByTimestamp(controller.getTimestamp());
    }

    function getCurrentReportingWindow() public view onlyInGoodTimes returns (IReportingWindow) {
        return getReportingWindowByTimestamp(controller.getTimestamp());
    }

    function getOrCreateNextReportingWindow() public onlyInGoodTimes returns (IReportingWindow) {
        return getOrCreateReportingWindowByTimestamp(controller.getTimestamp() + getReportingPeriodDurationInSeconds());
    }

    function getNextReportingWindow() public view onlyInGoodTimes returns (IReportingWindow) {
        return getReportingWindowByTimestamp(controller.getTimestamp() + getReportingPeriodDurationInSeconds());
    }

    function getOrCreateChildUniverse(bytes32 _parentPayoutDistributionHash) public returns (IUniverse) {
        require(forkingMarket != IMarket(0));
        if (childUniverses[_parentPayoutDistributionHash] == address(0)) {
            childUniverses[_parentPayoutDistributionHash] = UniverseFactory(controller.lookup("UniverseFactory")).createUniverse(controller, this, _parentPayoutDistributionHash);
            controller.getAugur().logUniverseCreated(childUniverses[_parentPayoutDistributionHash]);
        }
        return childUniverses[_parentPayoutDistributionHash];
    }

    function getRepAvailableForExtraBondPayouts() public view returns (uint256) {
        return repAvailableForExtraBondPayouts;
    }

    function increaseRepAvailableForExtraBondPayouts(uint256 _amount) public onlyInGoodTimes returns (bool) {
        require(msg.sender == address(reputationToken));
        repAvailableForExtraBondPayouts = repAvailableForExtraBondPayouts.add(_amount);
        return true;
    }

    function decreaseRepAvailableForExtraBondPayouts(uint256 _amount) public onlyInGoodTimes returns (bool) {
        require(parentUniverse.isContainerForDisputeBond(IDisputeBond(msg.sender)));
        repAvailableForExtraBondPayouts = repAvailableForExtraBondPayouts.sub(_amount);
        return true;
    }

    function isContainerForReportingWindow(IReportingWindow _shadyReportingWindow) public view returns (bool) {
        uint256 _startTime = _shadyReportingWindow.getStartTime();
        if (_startTime == 0) {
            return false;
        }
        uint256 _reportingWindowId = getReportingWindowId(_startTime);
        IReportingWindow _legitReportingWindow = reportingWindows[_reportingWindowId];
        return _shadyReportingWindow == _legitReportingWindow;
    }

    function isContainerForDisputeBond(IDisputeBond _shadyDisputeBond) public view returns (bool) {
        IMarket _shadyMarket = _shadyDisputeBond.getMarket();
        if (_shadyMarket == address(0)) {
            return false;
        }
        if (!isContainerForMarket(_shadyMarket)) {
            return false;
        }
        IMarket _legitMarket = _shadyMarket;
        return _legitMarket.isContainerForDisputeBond(_shadyDisputeBond);
    }

    function isContainerForMarket(IMarket _shadyMarket) public view returns (bool) {
        IReportingWindow _shadyReportingWindow = _shadyMarket.getReportingWindow();
        if (_shadyReportingWindow == address(0)) {
            return false;
        }
        if (!isContainerForReportingWindow(_shadyReportingWindow)) {
            return false;
        }
        IReportingWindow _legitReportingWindow = _shadyReportingWindow;
        return _legitReportingWindow.isContainerForMarket(_shadyMarket);
    }

    function isContainerForStakeToken(IStakeToken _shadyStakeToken) public view returns (bool) {
        IMarket _shadyMarket = _shadyStakeToken.getMarket();
        if (_shadyMarket == address(0)) {
            return false;
        }
        if (!isContainerForMarket(_shadyMarket)) {
            return false;
        }
        IMarket _legitMarket = _shadyMarket;
        return _legitMarket.isContainerForStakeToken(_shadyStakeToken);
    }

    function isContainerForShareToken(IShareToken _shadyShareToken) public view returns (bool) {
        IMarket _shadyMarket = _shadyShareToken.getMarket();
        if (_shadyMarket == address(0)) {
            return false;
        }
        if (!isContainerForMarket(_shadyMarket)) {
            return false;
        }
        IMarket _legitMarket = _shadyMarket;
        return _legitMarket.isContainerForShareToken(_shadyShareToken);
    }

    function isContainerForParticipationToken(IParticipationToken _shadyParticipationToken) public view returns (bool) {
        IReportingWindow _shadyReportingWindow = _shadyParticipationToken.getReportingWindow();
        if (_shadyReportingWindow == address(0)) {
            return false;
        }
        if (!isContainerForReportingWindow(_shadyReportingWindow)) {
            return false;
        }
        IReportingWindow _legitReportingWindow = _shadyReportingWindow;
        return _legitReportingWindow.isContainerForParticipationToken(_shadyParticipationToken);
    }

    function isParentOf(IUniverse _shadyChild) public view returns (bool) {
        bytes32 _parentPayoutDistributionHash = _shadyChild.getParentPayoutDistributionHash();
        return childUniverses[_parentPayoutDistributionHash] == _shadyChild;
    }

    function getOrCreateReportingWindowForForkEndTime() public returns (IReportingWindow) {
        return getOrCreateReportingWindowByTimestamp(getForkEndTime());
    }

    function getReportingWindowForForkEndTime() public view returns (IReportingWindow) {
        return getReportingWindowByTimestamp(getForkEndTime());
    }

    function decrementOpenInterest(uint256 _amount) public onlyInGoodTimes onlyWhitelistedCallers returns (bool) {
        openInterestInAttoEth = openInterestInAttoEth.sub(_amount);
        return true;
    }

    // CONSIDER: It would be more correct to decrease open interest for all outstanding shares in a market when it is finalized. We aren't doing this currently since securely and correctly writing this code would require updating the Market contract, which is currently at its size limit.
    function incrementOpenInterest(uint256 _amount) public onlyInGoodTimes onlyWhitelistedCallers returns (bool) {
        openInterestInAttoEth = openInterestInAttoEth.add(_amount);
        return true;
    }

    function getOpenInterestInAttoEth() public view returns (uint256) {
        return openInterestInAttoEth;
    }

    function getRepMarketCapInAttoeth() public view returns (uint256) {
        uint256 _attorepPerEth = IRepPriceOracle(controller.lookup("RepPriceOracle")).getRepPriceInAttoEth();
        uint256 _repMarketCapInAttoeth = getReputationToken().totalSupply() * _attorepPerEth;
        return _repMarketCapInAttoeth;
    }

    function getTargetRepMarketCapInAttoeth() public view returns (uint256) {
        return getOpenInterestInAttoEth() * Reporting.getTargetRepMarketCapMultiplier();
    }

    function getOrCacheValidityBond() public onlyInGoodTimes returns (uint256) {
        IReportingWindow _reportingWindow = getOrCreateCurrentReportingWindow();
        IReportingWindow  _previousReportingWindow = getOrCreatePreviousReportingWindow();
        // If the windows haven't been created yet return 0 to indicate this
        if (_reportingWindow == IReportingWindow(0) || _previousReportingWindow == IReportingWindow(0)) {
            return 0;
        }
        uint256 _currentValidityBondInAttoeth = validityBondInAttoeth[_reportingWindow];
        if (_currentValidityBondInAttoeth != 0) {
            return _currentValidityBondInAttoeth;
        }
        uint256 _totalMarketsInPreviousWindow = _previousReportingWindow.getNumMarkets();
        uint256 _invalidMarketsInPreviousWindow = _previousReportingWindow.getNumInvalidMarkets();
        uint256 _previousValidityBondInAttoeth = validityBondInAttoeth[_previousReportingWindow];
        _currentValidityBondInAttoeth = calculateFloatingValue(_invalidMarketsInPreviousWindow, _totalMarketsInPreviousWindow, Reporting.getTargetInvalidMarketsDivisor(), _previousValidityBondInAttoeth, Reporting.getDefaultValidityBond(), Reporting.getDefaultValidityBondFloor());
        validityBondInAttoeth[_reportingWindow] = _currentValidityBondInAttoeth;
        return _currentValidityBondInAttoeth;
    }

    function getOrCacheDesignatedReportStake() public onlyInGoodTimes returns (uint256) {
        IReportingWindow _reportingWindow = getOrCreateCurrentReportingWindow();
        IReportingWindow _previousReportingWindow = getOrCreatePreviousReportingWindow();
        uint256 _currentDesignatedReportStakeInAttoRep = designatedReportStakeInAttoRep[_reportingWindow];
        if (_currentDesignatedReportStakeInAttoRep != 0) {
            return _currentDesignatedReportStakeInAttoRep;
        }
        uint256 _totalMarketsInPreviousWindow = _previousReportingWindow.getNumMarkets();
        uint256 _incorrectDesignatedReportMarketsInPreviousWindow = _previousReportingWindow.getNumIncorrectDesignatedReportMarkets();
        uint256 _previousDesignatedReportStakeInAttoRep = designatedReportStakeInAttoRep[_previousReportingWindow];

        _currentDesignatedReportStakeInAttoRep = calculateFloatingValue(_incorrectDesignatedReportMarketsInPreviousWindow, _totalMarketsInPreviousWindow, Reporting.getTargetIncorrectDesignatedReportMarketsDivisor(), _previousDesignatedReportStakeInAttoRep, Reporting.getDefaultDesignatedReportStake(), Reporting.getDesignatedReportStakeFloor());
        designatedReportStakeInAttoRep[_reportingWindow] = _currentDesignatedReportStakeInAttoRep;
        return _currentDesignatedReportStakeInAttoRep;
    }

    function getOrCacheDesignatedReportNoShowBond() public onlyInGoodTimes returns (uint256) {
        IReportingWindow _reportingWindow = getOrCreateCurrentReportingWindow();
        IReportingWindow _previousReportingWindow = getOrCreatePreviousReportingWindow();
        uint256 _currentDesignatedReportNoShowBondInAttoRep = designatedReportNoShowBondInAttoRep[_reportingWindow];
        if (_currentDesignatedReportNoShowBondInAttoRep != 0) {
            return _currentDesignatedReportNoShowBondInAttoRep;
        }
        uint256 _totalMarketsInPreviousWindow = _previousReportingWindow.getNumMarkets();
        uint256 _designatedReportNoShowsInPreviousWindow = _previousReportingWindow.getNumDesignatedReportNoShows();
        uint256 _previousDesignatedReportNoShowBondInAttoRep = designatedReportNoShowBondInAttoRep[_previousReportingWindow];

        _currentDesignatedReportNoShowBondInAttoRep = calculateFloatingValue(_designatedReportNoShowsInPreviousWindow, _totalMarketsInPreviousWindow, Reporting.getTargetDesignatedReportNoShowsDivisor(), _previousDesignatedReportNoShowBondInAttoRep, Reporting.getDefaultDesignatedReportNoShowBond(), Reporting.getDesignatedReportNoShowBondFloor());
        designatedReportNoShowBondInAttoRep[_reportingWindow] = _currentDesignatedReportNoShowBondInAttoRep;
        return _currentDesignatedReportNoShowBondInAttoRep;
    }

    function calculateFloatingValue(uint256 _badMarkets, uint256 _totalMarkets, uint256 _targetDivisor, uint256 _previousValue, uint256 _defaultValue, uint256 _floor) public pure returns (uint256 _newValue) {
        if (_totalMarkets == 0) {
            return _defaultValue;
        }
        if (_previousValue == 0) {
            _previousValue = _defaultValue;
        }

        // Modify the amount based on the previous amount and the number of markets fitting the failure criteria. We want the amount to be somewhere in the range of 0.5 to 2 times its previous value where ALL markets with the condition results in 2x and 0 results in 0.5x.
        if (_badMarkets <= _totalMarkets / _targetDivisor) {
            // FXP formula: previous_amount * actual_percent / (2 * target_percent) + 0.5;
            _newValue = _badMarkets
                .mul(_previousValue)
                .mul(_targetDivisor)
                .div(_totalMarkets)
                .div(2) + _previousValue / 2;
        } else {
            // FXP formula: previous_amount * (1/(1 - target_percent)) * (actual_percent - target_percent) + 1;
            _newValue = _targetDivisor
                .mul(_previousValue
                    .mul(_badMarkets)
                    .div(_totalMarkets)
                    .sub(_previousValue
                        .div(_targetDivisor)))
                .div(_targetDivisor - 1) + _previousValue;
        }

        _newValue = _newValue.max(_floor);

        return _newValue;
    }

    function getOrCacheReportingFeeDivisor() public onlyInGoodTimes returns (uint256) {
        IReportingWindow _reportingWindow = getOrCreateCurrentReportingWindow();
        IReportingWindow _previousReportingWindow = getOrCreatePreviousReportingWindow();
        uint256 _currentFeeDivisor = shareSettlementFeeDivisor[_reportingWindow];
        if (_currentFeeDivisor != 0) {
            return _currentFeeDivisor;
        }
        uint256 _repMarketCapInAttoeth = getRepMarketCapInAttoeth();
        uint256 _targetRepMarketCapInAttoeth = getTargetRepMarketCapInAttoeth();
        uint256 _previousFeeDivisor = shareSettlementFeeDivisor[_previousReportingWindow];
        if (_previousFeeDivisor == 0) {
            _previousFeeDivisor = Reporting.getDefaultReportingFeeDivisor();
        }
        if (_targetRepMarketCapInAttoeth == 0) {
            _currentFeeDivisor = Reporting.getMaximumReportingFeeDivisor();
        } else {
            _currentFeeDivisor = _previousFeeDivisor * _repMarketCapInAttoeth / _targetRepMarketCapInAttoeth;
        }

        _currentFeeDivisor = _currentFeeDivisor
            .max(Reporting.getMinimumReportingFeeDivisor())
            .min(Reporting.getMaximumReportingFeeDivisor());

        shareSettlementFeeDivisor[_reportingWindow] = _currentFeeDivisor;
        return _currentFeeDivisor;
    }

    function getOrCacheTargetReporterGasCosts() public onlyInGoodTimes returns (uint256) {
        IReportingWindow _reportingWindow = getOrCreateCurrentReportingWindow();
        IReportingWindow _previousReportingWindow = getOrCreatePreviousReportingWindow();
        uint256 _getGasToReport = targetReporterGasCosts[_reportingWindow];
        if (_getGasToReport != 0) {
            return _getGasToReport;
        }

        uint256 _avgGasPrice = _previousReportingWindow.getAvgReportingGasPrice();
        _getGasToReport = Reporting.getGasToReport();
        // we double it to try and ensure we have more than enough rather than not enough
        targetReporterGasCosts[_reportingWindow] = _getGasToReport * _avgGasPrice * 2;
        return targetReporterGasCosts[_reportingWindow];
    }

    function getOrCacheMarketCreationCost() public onlyInGoodTimes returns (uint256) {
        return getOrCacheValidityBond() + getOrCacheTargetReporterGasCosts();
    }

    function createBinaryMarket(uint256 _endTime, uint256 _feePerEthInWei, ICash _denominationToken, address _designatedReporterAddress, bytes32 _topic, string _description, string _extraInfo) public onlyInGoodTimes afterInitialized payable returns (IMarket _newMarket) {
        require(bytes(_description).length > 0);
        IReportingWindow _reportingWindow = getOrCreateReportingWindowByMarketEndTime(_endTime);
        _newMarket = _reportingWindow.createMarket.value(msg.value)(_endTime, _feePerEthInWei, _denominationToken, _designatedReporterAddress, msg.sender, 2, Reporting.getCategoricalMarketNumTicks(2));
        controller.getAugur().logMarketCreated(getOrCacheMarketCreationCost(), 0, 1, IMarket.MarketType.BINARY, _topic, _description, _extraInfo, this, _newMarket, msg.sender);
        return _newMarket;
    }

    function createCategoricalMarket(uint256 _endTime, uint256 _feePerEthInWei, ICash _denominationToken, address _designatedReporterAddress, uint8 _numOutcomes, bytes32 _topic, string _description, string _extraInfo) public onlyInGoodTimes afterInitialized payable returns (IMarket _newMarket) {
        require(bytes(_description).length > 0);
        IReportingWindow _reportingWindow = getOrCreateReportingWindowByMarketEndTime(_endTime);
        _newMarket = _reportingWindow.createMarket.value(msg.value)(_endTime, _feePerEthInWei, _denominationToken, _designatedReporterAddress, msg.sender, _numOutcomes, Reporting.getCategoricalMarketNumTicks(_numOutcomes));
        controller.getAugur().logMarketCreated(getOrCacheMarketCreationCost(), 0, 1, IMarket.MarketType.CATEGORICAL, _topic, _description, _extraInfo, this, _newMarket, msg.sender);
        return _newMarket;
    }

    function createScalarMarket(uint256 _endTime, uint256 _feePerEthInWei, ICash _denominationToken, address _designatedReporterAddress, int256 _minPrice, int256 _maxPrice, uint256 _numTicks, bytes32 _topic, string _description, string _extraInfo) public onlyInGoodTimes afterInitialized payable returns (IMarket _newMarket) {
        require(bytes(_description).length > 0);
        require(_minPrice < _maxPrice);
        IReportingWindow _reportingWindow = getOrCreateReportingWindowByMarketEndTime(_endTime);
        _newMarket = _reportingWindow.createMarket.value(msg.value)(_endTime, _feePerEthInWei, _denominationToken, _designatedReporterAddress, msg.sender, 2, _numTicks);
        controller.getAugur().logMarketCreated(getOrCacheMarketCreationCost(), _minPrice, _maxPrice, IMarket.MarketType.SCALAR, _topic, _description, _extraInfo, this, _newMarket, msg.sender);
        return _newMarket;
    }

    function redeemStake(IStakeToken[] _stakeTokens, IDisputeBond[] _disputeBonds, IParticipationToken[] _participationTokens, bool forgoFees) public onlyInGoodTimes returns (bool) {
        for (uint8 i=0; i < _stakeTokens.length; i++) {
            IStakeToken _stakeToken = _stakeTokens[i];
            if (_stakeToken.isDisavowed()) {
                _stakeToken.redeemDisavowedTokens(msg.sender);
            } else if (_stakeToken.isForked()) {
                _stakeToken.redeemForkedTokensForHolder(msg.sender);
            } else {
                _stakeToken.redeemWinningTokensForHolder(msg.sender, forgoFees);
            }
        }

        for (uint8 j=0; j < _disputeBonds.length; j++) {
            IDisputeBond _disputeBond = _disputeBonds[j];
            if (_disputeBond.isDisavowed()) {
                _disputeBond.withdrawDisavowedTokens();
            } else {
                _disputeBond.withdrawForHolder(msg.sender, forgoFees);
            }
        }

        for (uint8 k=0; k < _participationTokens.length; k++) {
            IParticipationToken _participationToken = _participationTokens[k];
            _participationToken.redeemForHolder(msg.sender, forgoFees);
        }

        return true;
    }

    function getProtectedTokens() internal returns (address[] memory) {
        return new address[](0);
    }
}
