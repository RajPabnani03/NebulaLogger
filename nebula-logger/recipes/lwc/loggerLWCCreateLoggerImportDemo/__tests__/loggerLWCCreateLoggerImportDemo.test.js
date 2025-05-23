import { createElement } from 'lwc';
import { getLogger } from 'c/logger';
import loggerLWCCreateLoggerImportDemo from 'c/loggerLWCCreateLoggerImportDemo';

import getSettings from '@salesforce/apex/ComponentLogger.getSettings';

const flushPromises = async () => {
  await new Promise(process.nextTick);
};

const MOCK_GET_SETTINGS = {
  defaultSaveMethod: 'EVENT_BUS',
  isEnabled: true,
  isConsoleLoggingEnabled: true,
  supportedLoggingLevels: { FINEST: 2, FINER: 3, FINE: 4, DEBUG: 5, INFO: 6, WARN: 7, ERROR: 8 },
  userLoggingLevel: { ordinal: 2, name: 'FINEST' }
};

jest.mock('lightning/logger', () => ({ log: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/ComponentLogger.getSettings',
  () => {
    return {
      default: jest.fn()
    };
  },
  { virtual: true }
);

describe('logger demo tests', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('mounts and saves log correctly in one go', async () => {
    getSettings.mockResolvedValue({ ...MOCK_GET_SETTINGS });
    const demo = createElement('c-logger-demo', { is: loggerLWCCreateLoggerImportDemo });

    document.body.appendChild(demo);
    await flushPromises('Resolve async tasks from mounting component');

    expect(demo.logger).toBeDefined();
    expect(demo.logger.getBufferSize()).toBe(0);
  });
});
