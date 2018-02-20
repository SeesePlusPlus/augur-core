import { URL } from 'url';
import { NetworkConfiguration } from '../libraries/NetworkConfiguration';
import { server as serverFactory } from 'ganache-core';
import { CompilerOutput } from 'solc';
import { CompilerConfiguration } from '../libraries/CompilerConfiguration';

export class TestRpc {
    private readonly DEFAULT_TEST_ACCOUNT_BALANCE = 10**20;
    private readonly BLOCK_GAS_LIMIT = 6500000;
    private readonly BLOCK_GAS_LIMIT_SDB = 10000000;
    private readonly networkConfiguration: NetworkConfiguration;
    private readonly compilerConfiguration: CompilerConfiguration;
    private readonly testRpcServer: any;

    constructor(networkConfiguration: NetworkConfiguration, compilerConfiguration: CompilerConfiguration) {
        this.networkConfiguration = networkConfiguration;
        this.compilerConfiguration = compilerConfiguration;
        const blockGasLimit = this.compilerConfiguration.enableSdb ? this.BLOCK_GAS_LIMIT_SDB : this.BLOCK_GAS_LIMIT;
        const accounts = [{ balance: `0x${this.DEFAULT_TEST_ACCOUNT_BALANCE.toString(16)}`, secretKey: networkConfiguration.privateKey }];
        const options = { gasLimit: `0x${blockGasLimit.toString(16)}`, accounts: accounts };
        this.testRpcServer = serverFactory(options);
    }

    public listen(): void {
        const url = new URL(this.networkConfiguration.http);
        this.testRpcServer.listen(parseInt(url.port) || 80);
    }

    public static startTestRpcIfNecessary = async (networkConfiguration: NetworkConfiguration, compilerConfiguration: CompilerConfiguration): Promise<TestRpc | null> => {
        if (networkConfiguration.networkName === 'testrpc') {
            const testRpc = new TestRpc(networkConfiguration, compilerConfiguration);
            testRpc.listen();
            return testRpc;
        }
        else {
            return null;
        }
    }

    public linkDebugSymbols = async (compilerOutput: CompilerOutput, addressMapping: any): Promise<void> => {
        const sdbHook = this.testRpcServer.provider.manager.state.sdbHook;
        if (sdbHook) {
            sdbHook.linkCompilerOutput(this.compilerConfiguration.contractSourceRoot, compilerOutput);
            const keys = Object.keys(addressMapping);
            for (let i = 0; i < keys.length; i++) {
                const contractName = keys[i];
                sdbHook.linkContractAddress(contractName, addressMapping[keys[i]]);
            }
        }
    }
}
