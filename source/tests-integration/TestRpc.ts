import { Configuration } from '../libraries/Configuration';
import { Connector } from '../libraries/Connector';
import { server as serverFactory } from 'ganache-core';
import { CompilerOutput } from 'solc';

export class TestRpc {
    private readonly DEFAULT_TEST_ACCOUNT_BALANCE = 10**20;
    private readonly BLOCK_GAS_LIMIT = 6500000;
    private readonly BLOCK_GAS_LIMIT_SDB = 10000000;
    private readonly configuration: Configuration;
    private testRpcServer: any;

    constructor(configuration: Configuration) {
        this.configuration = configuration;

        const blockGasLimit = this.configuration.enableSdb ? this.BLOCK_GAS_LIMIT_SDB : this.BLOCK_GAS_LIMIT;

        const accounts = [{ balance: `0x${this.DEFAULT_TEST_ACCOUNT_BALANCE.toString(16)}`, secretKey: configuration.privateKey }];
        const options = { gasLimit: `0x${blockGasLimit.toString(16)}`, accounts: accounts, sdb: this.configuration.enableSdb };
        this.testRpcServer = serverFactory(options);
        this.testRpcServer.listen(configuration.httpProviderPort);
    }

    public waitForStartup = async () => {
        await new Connector(this.configuration).waitUntilConnected();
    }

    public static startTestRpcIfNecessary = async (configuration: Configuration): Promise<TestRpc | null> => {
        if (typeof process.env.ETHEREUM_HOST !== "undefined") return null;
        const testRpc = new TestRpc(configuration);
        await testRpc.waitForStartup();
        return testRpc;
    }

    public linkDebugSymbols = async (compilerOutput: CompilerOutput, addressMapping: any): Promise<void> => {
        const sdbHook = this.testRpcServer.provider.manager.state.sdbHook;
        if (sdbHook) {
            sdbHook.linkCompilerOutput(this.configuration.contractSourceRoot, compilerOutput);
            const keys = Object.keys(addressMapping);
            for (let i = 0; i < keys.length; i++) {
                const contractName = keys[i];
                sdbHook.linkContractAddress(contractName, addressMapping[keys[i]]);
            }
        }
    }
}
