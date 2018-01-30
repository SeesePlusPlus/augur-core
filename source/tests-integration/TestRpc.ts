import { Configuration } from '../libraries/Configuration';
import { Connector } from '../libraries/Connector';
import { server as serverFactory, TestRpcServer } from 'ethereumjs-testrpc';
import { CompilerOutput } from 'solc';

export class TestRpc {
    private readonly DEFAULT_TEST_ACCOUNT_BALANCE = 10**20;
    private readonly BLOCK_GAS_LIMIT = 6500000;
    private readonly configuration: Configuration;
    private testRpcServer: TestRpcServer;

    constructor(configuration: Configuration) {
        this.configuration = configuration;
        const accounts = [{ balance: `0x${this.DEFAULT_TEST_ACCOUNT_BALANCE.toString(16)}`, secretKey: configuration.privateKey }];
        const options = { gasLimit: `0x${this.BLOCK_GAS_LIMIT.toString(16)}`, accounts: accounts };
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

    public linkDebugSymbols = async (compilerOutput: CompilerOutput, addressMapping: { [name: string]: string }): Promise<void> => {
        const sdbHook = this.testRpcServer.provider.manager.state.sdbHook;
        if (sdbHook) {
            sdbHook.linkCompilerOutput(compilerOutput);
            const keys = Object.keys(addressMapping);
            for (let i = 0; i < keys.length; i++) {
                const contractName = addressMapping[keys[i]];
                sdbHook.linkContractAddress(this.configuration.contractSourceRoot, contractName, keys[i]);
            }
        }
    }
}
